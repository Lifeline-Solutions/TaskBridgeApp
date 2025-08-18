class SystemMailer < ApplicationMailer
  default from: ENV.fetch('MAIL_FROM', 'cspm@craftsilicon.com')

  def generic(email_id)
    @email = Email.find(email_id)

    # Attach any uploaded files first
    @email.attachments.each do |att|
      attachments[att.filename.to_s] = {
        mime_type: att.content_type,
        content: att.download
      }
    end

    # Ensure a safe from address for legacy rows
    allowed_from = begin
      candidate = @email.from_address.to_s.strip
      if candidate.blank? || candidate.casecmp('no-reply@example.com').zero? || candidate.downcase.end_with?('@example.com')
        self.class.default_params[:from]
      else
        candidate
      end
    end

    # Filter recipients to exclude deactivated users (defense-in-depth)
    filtered_to = if defined?(Messaging::EmailSender)
                    Messaging::EmailSender.filter_active_emails(@email.to_list)
                  else
                    @email.to_list
                  end
    filtered_cc = if defined?(Messaging::EmailSender)
                    Messaging::EmailSender.filter_active_emails(@email.cc_list)
                  else
                    @email.cc_list
                  end
    filtered_bcc = if defined?(Messaging::EmailSender)
                     Messaging::EmailSender.filter_active_emails(@email.bcc_list)
                   else
                     @email.bcc_list
                   end

    mail(
      to: filtered_to.presence,
      cc: filtered_cc.presence,
      bcc: filtered_bcc.presence,
      from: allowed_from,
      subject: @email.subject
    ) do |format|
      template = @email.extra.is_a?(Hash) ? @email.extra['template'] : nil
      if template
        assigns = template['assigns'] || {}
        assigns = decode_assigns(assigns)
        assigns.each { |k, v| instance_variable_set("@#{k}", v) }
        layout = template['layout']
        html_view = template['view']
        text_view = template['text_view']
        format.html { render html_view, layout: layout } if html_view
        format.text { render text_view, layout: layout } if text_view
      else
        format.html { render html: @email.body_html.html_safe } if @email.body_html.present?
        format.text { render plain: @email.body_text } if @email.body_text.present?
      end
    end
  end

  private

  # Turn encoded or legacy Hash assigns into ActiveRecord models/values expected by views
  def decode_assigns(assigns)
    assigns.each_with_object({}) do |(k, v), h|
      h[k] = decode_value_for(k, v)
    end
  end

  def decode_value_for(key, value)
    case value
    when Array
      value.map { |e| decode_value_for(nil, e) }
    when Hash
      # Encoded format: { '__model__' => 'Class', 'id' => '...' }
      if value.key?('__model__') && value.key?('id')
        klass = safe_constantize(value['__model__'])
        return safe_find(klass, value['id']) if klass
      end
      # Heuristic for legacy hashes: infer model from assign key name
      inferred_class = infer_class_from_key(key)
      if inferred_class && value.key?('id')
        rec = safe_find(inferred_class, value['id'])
        return rec if rec
      end
      value
    else
      value
    end
  end

  def infer_class_from_key(key)
    return nil unless key

    k = key.to_s
    if k.end_with?('user') || k.include?('user')
      User
    else
      mapping = {
        'ticket' => Ticket,
        'project' => Project,
        'issue' => Issue,
        'comment' => Comment,
        'product' => Product,
        'task' => Task,
        'groupware' => Groupware,
        'software' => Software
      }
      mapping[k]
    end
  rescue NameError
    nil
  end

  def safe_constantize(name)
    name.to_s.safe_constantize
  end

  def safe_find(klass, id)
    return nil unless klass && id

    klass.find_by(id: id)
  rescue StandardError
    nil
  end
end
