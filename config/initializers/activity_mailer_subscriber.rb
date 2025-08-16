# Logs an activity for every email delivery
return unless defined?(Activities)

ActiveSupport::Notifications.subscribe('deliver.action_mailer') do |_name, _start, _finish, _id, payload|
  begin
    mail = payload[:mail]
  # Skip SystemMailer to avoid duplicate email_sent logs (EmailDispatchJob already logs)
  next if payload[:mailer].to_s == 'SystemMailer'
    Activities.activity
      .caused_by(defined?(Current) ? Current.user : nil)
      .event('email_sent')
      .with_properties(
        mailer: payload[:mailer],
        action: payload[:action],
        message_id: (mail.respond_to?(:message_id) ? mail.message_id : nil),
        to: (mail.respond_to?(:to) ? Array(mail.to) : []),
        cc: (mail.respond_to?(:cc) ? Array(mail.cc) : []),
        bcc: (mail.respond_to?(:bcc) ? Array(mail.bcc) : []),
        subject: (mail.respond_to?(:subject) ? mail.subject : nil),
        delivery_method: payload[:delivery_method].to_s
      )
      .log("Email sent: #{payload[:mailer]}##{payload[:action] || (mail.respond_to?(:subject) ? mail.subject : 'unknown')}")
  rescue => e
    Rails.logger.debug("Activity mailer subscriber failed: #{e.message}")
  end
end
