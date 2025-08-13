class ErrorNotifierMailer < ApplicationMailer
  default to: -> { ['robert.mbugua@craftsilicon.com'] },
          from: 'cspm@craftsilicon.com'

  # Accept a serializable payload hash
  def notify_error(payload)
    @payload = payload

    log_path = Rails.root.join('log', 'production_errors.log')
    attachments['production_errors.log'] = File.read(log_path) if File.exist?(log_path)

    subj = "[Rails Error] #{@payload[:exception_class]} - #{@payload[:message].to_s.truncate(80)}"
    mail(subject: subj)
  end
end
