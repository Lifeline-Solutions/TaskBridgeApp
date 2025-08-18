class ApplicationMailer < ActionMailer::Base
  # default from: 'from@example.com'
  # layout 'mailer'
  default from: 'cspm@craftsilicon.com'

  def reset_password_instructions(record, token, opts = {})
    super
  end

  # Central recipient filter for any direct mailers inheriting from ApplicationMailer
  def mail(headers = {}, &)
    headers = headers.dup
    if defined?(Messaging::EmailSender)
      headers[:to] = Messaging::EmailSender.filter_active_emails(headers[:to]) if headers.key?(:to)
      headers[:cc] = Messaging::EmailSender.filter_active_emails(headers[:cc]) if headers.key?(:cc)
      headers[:bcc] = Messaging::EmailSender.filter_active_emails(headers[:bcc]) if headers.key?(:bcc)

      # If all recipients are filtered, do not attempt to send
      to_blank = Array(headers[:to]).compact.blank?
      cc_blank = Array(headers[:cc]).compact.blank?
      bcc_blank = Array(headers[:bcc]).compact.blank?
      return if to_blank && cc_blank && bcc_blank
    end
    super
  end
end
