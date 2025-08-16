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

    queue_flag = async_delivery?
    subject = "[Error] #{payload[:exception_class]}: #{payload[:message].to_s.truncate(80)}"
    body_html = "<pre>#{ERB::Util.html_escape(payload[:message])}</pre>"
    Messaging::EmailSender
      .send_email(
        subject,
        body: body_html,
        to: Array(payload[:to]).presence || env_recipients,
        actor: nil,
        priority: :high,
        type: 'error_notification'
      )
      .set_source('system_activity', nil)
      .send(queue: queue_flag)
  rescue StandardError => e
    Rails.logger.warn("ErrorNotifierMailer delivery failed (#{e.class}): #{e.message}.")
  Rails.logger.error("SafeNotifier fallback suppressed; emails now persisted via Emails table")
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
