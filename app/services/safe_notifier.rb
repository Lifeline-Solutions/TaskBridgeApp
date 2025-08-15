require 'digest'
module SafeNotifier
  module_function

  def email(exception, context: nil)
    recipients = env_recipients
    payload = ErrorPayload.build(exception, context: context)
    payload[:to] = recipients if recipients.any?

    # dedup/throttle by fingerprint
    if throttled?(payload)
      Rails.logger.info("SafeNotifier: throttled duplicate error #{fingerprint(payload)}")
      return
    end

    if async_delivery?
      ErrorNotifierMailer.notify_error(payload).deliver_later
    else
      ErrorNotifierMailer.notify_error(payload).deliver_now
    end
  rescue StandardError => e
    Rails.logger.warn("ErrorNotifierMailer delivery failed (#{e.class}): #{e.message}.")
    begin
      ErrorNotifierMailer.notify_error(payload).deliver_now
    rescue StandardError => send_err
      Rails.logger.error("deliver_now failed (#{send_err.class}): #{send_err.message}")
    end
  end

  def async_delivery?
    ENV.fetch('ERROR_NOTIFY_ASYNC', 'false') == 'true'
  end

  def env_recipients
    raw = ENV.fetch('ERROR_NOTIFY_TO', nil)
    return [] unless raw.present?

    raw.split(',').map(&:strip).reject(&:blank?)
  end

  def throttled?(payload)
    ttl = Integer(ENV.fetch('ERROR_NOTIFY_THROTTLE_SECONDS', '300'))
    return false if ttl <= 0

    key = "safe_notifier:fingerprint:#{fingerprint(payload)}"
    # Use Rails.cache if available; if not, do not throttle
    cache = defined?(Rails) && Rails.respond_to?(:cache) ? Rails.cache : nil
    return false unless cache

    cache.fetch(key, expires_in: ttl, race_condition_ttl: 5) do
      # First time: write key and allow send
      :written
    end != :written
  rescue StandardError => _e
    false
  end

  def fingerprint(payload)
    klass = payload[:exception_class]
    msg = payload[:message].to_s[0, 120]
    bt0 = Array(payload[:backtrace]).first.to_s
    Digest::SHA256.hexdigest([klass, msg, bt0].join('|'))
  end
end
