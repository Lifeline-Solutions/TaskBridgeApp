class ErrorNotifierMailer < ApplicationMailer
  default to: -> { ["robert.mbugua@craftsilicon.com"] },
          from: "cspm@craftsilicon.com"

  def notify_error(exception, context: nil)
    @exception = exception
    @context = context

    log_path = Rails.root.join("log", "errors.log")
    attachments["errors.log"] = File.read(log_path) if File.exist?(log_path)

    mail(subject: "[Rails Error] #{exception.class} - #{exception.message.truncate(80)}")
  end
end