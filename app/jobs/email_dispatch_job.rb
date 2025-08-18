class EmailDispatchJob < ApplicationJob
  queue_as :mailers

  def perform(email_id)
    email = Email.find_by(id: email_id)
    return unless email&.status_queued?

    email.mark_sending!
    # Defense-in-depth: compute filtered recipients right before send
    filtered_to = defined?(Messaging::EmailSender) ? Messaging::EmailSender.filter_active_emails(email.to_list) : email.to_list
    filtered_cc = defined?(Messaging::EmailSender) ? Messaging::EmailSender.filter_active_emails(email.cc_list) : email.cc_list
    filtered_bcc = defined?(Messaging::EmailSender) ? Messaging::EmailSender.filter_active_emails(email.bcc_list) : email.bcc_list

    # If all recipients are filtered out, fail gracefully and skip SMTP
    if filtered_to.blank? && filtered_cc.blank? && filtered_bcc.blank?
      email.mark_failed!(reason: 'No active recipients')
      Activities.activity
        .event('email_skipped')
        .performed_on(email)
        .with_properties({ reason: 'no_active_recipients', subject: email.subject })
        .log("Email skipped (no active recipients) #{email.subject}")
      return
    end

    mail = SystemMailer.generic(email.id)
    mail.deliver_now
    message_id = mail.message_id

    email.mark_sent!(message_id: message_id)
    Activities.activity
      .event('email_sent')
      .performed_on(email)
      .with_properties({ message_id: message_id, to: email.to_list, subject: email.subject })
      .log("Email sent #{email.subject}")
  rescue StandardError => e
    email&.mark_failed!(reason: e.message)
    Activities.activity
      .event('email_failed')
      .performed_on(email || Email.new)
      .with_properties({ error: e.class.name, message: e.message })
      .log("Email failed #{email&.subject}")
    raise e if ENV['EMAIL_RAISE_ON_FAIL'] == 'true'
  end
end
