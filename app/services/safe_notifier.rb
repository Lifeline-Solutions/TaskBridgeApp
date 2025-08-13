module SafeNotifier
  module_function

  def email(exception, context: nil)
    payload = ErrorPayload.build(exception, context: context)
    ErrorNotifierMailer.notify_error(payload).deliver_later
  rescue StandardError => e
    Rails.logger.warn("deliver_later failed (#{e.class}): #{e.message}. Falling back to deliver_now.")
    begin
      ErrorNotifierMailer.notify_error(payload).deliver_now
    rescue StandardError => send_err
      Rails.logger.error("deliver_now failed (#{send_err.class}): #{send_err.message}")
    end
  end
end
