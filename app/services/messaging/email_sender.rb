module Messaging
  class EmailSender
    def self.send_email(subject,
                        to:, body: nil,
                        text: nil,
                        cc: nil,
                        bcc: nil,
                        from: ENV.fetch('MAIL_FROM', 'cspm@craftsilicon.com'),
                        actor: Current.user,
                        priority: :normal,
                        type: nil)
      Builder.new(subject:, body:, text:, to:, cc:, bcc:, from:, actor:, priority:, type:)
    end

    class Builder
      def initialize(subject:, body:, text:, to:, cc:, bcc:, from:, actor:, priority:, type:)
        @email = Email.new(
          subject: subject,
          body_html: body,
          body_text: text,
          priority: priority.to_s,
          email_type: type,
          from_address: from,
          created_on: Time.current,
          modified_on: Time.current
        )
        @actor = actor
        @email.to = to
        @email.cc = cc if cc
        @email.bcc = bcc if bcc
        @email.extra ||= {}
      end

      def set_source(model_class_or_key, id)
        key = model_key(model_class_or_key)
        @email.source_type = key
        @email.source_id = id
        self
      end

      def set_party(model_class_or_key, id)
        key = model_key(model_class_or_key)
        @email.party_type = key
        @email.party_id = id
        self
      end

      def set_mail_id(value)
        @email.mail_id = value
        self
      end

      def set_conversation(id)
        @email.email_conversation_id = id
        self
      end

      def set_reference(id)
        @email.reference_id = id
        self
      end

      def add_attachment_content(bytes:, filename:, content_type:)
        io = StringIO.new(bytes)
        @email.attachments.attach(io:, filename:, content_type:)
        self
      end

      def add_attachment(io:, filename:, content_type:)
        @email.attachments.attach(io:, filename:, content_type:)
        self
      end

      # Use a Rails view template for the email body instead of raw HTML/text.
      # Example: use_template(view: 'user_mailer/daily_ticket_email', assigns: { user: u, tickets: arr })
      def use_template(view:, text_view: nil, assigns: {}, layout: nil)
        tpl = {
          'view' => view,
          'text_view' => text_view,
          'assigns' => encode_assigns(assigns),
          'layout' => layout
        }.compact
        @email.extra ||= {}
        @email.extra['template'] = tpl
        self
      end

      def send(queue: true)
        @email.save!

        @email.update_columns(party_type: ::ActivityMorphMap.class_to_key(@actor.class), party_id: @actor.id) if @email.party_type.blank? && @actor

        Activities.activity
          .event('email_queued')
          .performed_on(@email)
          .with_properties({ to: @email.to_list, subject: @email.subject, priority: @email.priority })
          .log("Email queued #{@email.subject}")

        if queue
          EmailDispatchJob.perform_later(@email.id)
        else
          EmailDispatchJob.perform_now(@email.id)
        end

        @email
      end

      private

      def model_key(klass_or_key)
        return klass_or_key.to_s if klass_or_key.is_a?(String)
        return klass_or_key.name if klass_or_key.is_a?(Module)

        klass_or_key.class.name
      end

      # Convert ActiveRecord objects to lightweight references for JSON storage
      def encode_assigns(assigns)
        assigns.transform_values { |v| encode_value(v) }
      end

      def encode_value(v)
        case v
        when ActiveRecord::Base
          { '__model__' => v.class.name, 'id' => v.id }
        when Array
          v.map { |e| encode_value(e) }
        when Hash
          v.transform_values { |e| encode_value(e) }
        else
          v
        end
      end
    end
  end
end
