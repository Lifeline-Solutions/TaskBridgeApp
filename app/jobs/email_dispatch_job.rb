class EmailDispatchJob < ApplicationJob
  queue_as :mailers

  def perform(email_id)
    email = Email.find_by(id: email_id)
    return unless email && email.status_queued?

    email.mark_sending!
  mail = SystemMailer.generic(email.id)
    mail.deliver_now
    message_id = mail.message_id

    email.mark_sent!(message_id: message_id)
    Activities.activity
      .event('email_sent')
      .performed_on(email)
      .with_properties({ message_id: message_id, to: email.to_list, subject: email.subject })
      .log("Email sent #{email.subject}")
  rescue => e
    email&.mark_failed!(reason: e.message)
    Activities.activity
      .event('email_failed')
      .performed_on(email || Email.new)
      .with_properties({ error: e.class.name, message: e.message })
      .log("Email failed #{email&.subject}")
    raise e if ENV['EMAIL_RAISE_ON_FAIL'] == 'true'
  end
end
