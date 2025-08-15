class ErrorNotifierMailer < ApplicationMailer
  default to: -> { ['robert.mbugua@craftsilicon.com'] },
          from: 'cspm@craftsilicon.com'

  # Accept a serializable payload hash
  def notify_error(payload)
    @payload = payload

    log_path = Rails.root.join('log', 'production_errors.log')
    attachments['production_errors.log'] = File.read(log_path) if File.exist?(log_path)

    subj = "[Rails Error] #{@payload[:exception_class]} - #{@payload[:message].to_s[0, 80]}"
    summary_lines = []
    summary_lines << "Exception: #{@payload[:exception_class]}"
    summary_lines << "Message: #{@payload[:message]}"
    summary_lines << "When: #{@payload[:occurred_at]}"
    summary_lines << "Context: #{(@payload[:context] || {}).inspect}"
    summary_lines << "Backtrace:\n#{Array(@payload[:backtrace]).join("\n")}"
    mail_args = { subject: subj, body: summary_lines.join("\n") }
    # allow overriding recipients via payload[:to]
    if (rcpts = Array(@payload[:to]).reject(&:blank?)).any?
      mail_args[:to] = rcpts
    end
    mail(mail_args)
  end
end
