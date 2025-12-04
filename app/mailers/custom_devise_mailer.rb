class CustomDeviseMailer < Devise::Mailer
  helper :application
  include Devise::Controllers::UrlHelpers

  default template_path: 'devise/mailer'
  def invitation_instructions(record, token, opts = {})
    # Never send to deactivated users
    return if record.respond_to?(:active) && record.active == false

    @token = token
    @resource = record
    if record.has_role?(:ceo)
      opts[:from] = 'fokwaro@craftsilicon.com'
      opts[:subject] = 'Your Support Portal Access (TaskBridge)'
      opts[:bcc] = 'fokwaro@craftsilicon.com'
      mail(opts.merge(to: record.email)) do |format|
        format.html { render 'devise/mailer/invitation_ceo' }
      end
    else
      opts[:from] = 'cspm@craftsilicon.com'
      opts[:subject] = 'Your Support Portal Access (TaskBridge)'
      # Use Devise's default rendering but still respect the to: and from: set above
      super if record.respond_to?(:email) && record.email.present?
    end
  end

  def reset_password_instructions(record, token, opts = {})
    # Never send to deactivated users
    return if record.respond_to?(:active) && record.active == false

    # Use Messaging::EmailSender to persist the email
    @resource = record
    @token = token
    
    email_body = render_to_string(
      template: 'devise/mailer/reset_password_instructions',
      layout: 'mailer'
    )

    sender = Messaging::EmailSender.send_email(
      opts[:subject] || 'Reset password instructions',
      to: record.email,
      from: opts[:from] || ENV.fetch('MAIL_FROM', 'cspm@craftsilicon.com'),
      body: email_body,
      type: 'reset_password',
      actor: record
    )

    sender.send

    # Return a dummy object that satisfies Devise's expectation of a mail object
    # that responds to deliver_now/deliver_later
    OpenStruct.new(deliver: true, deliver_now: true, deliver_later: true)
  end
end
