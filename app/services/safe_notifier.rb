require 'digest'
module SafeNotifier
  module_function

  def email(exception, context: nil)
    # Only send emails when explicitly flagged as a complete system break
    unless system_break?(context)
      Rails.logger.info("SafeNotifier: email suppressed (non system-break) for #{exception.class}")
      return
    end

    Rails.logger.info("SafeNotifier: preparing system-break email for #{exception.class} - #{exception.message}")
    recipients = env_recipients
    payload = ErrorPayload.build(exception, context: context)
    payload[:to] = recipients if recipients.any?

    # dedup/throttle by fingerprint
    if throttled?(payload)
      Rails.logger.info("SafeNotifier: throttled duplicate error #{fingerprint(payload)}")
      return
    end

    queue_flag = async_delivery?
    subject = "[SYSTEM BREAK] #{payload[:exception_class]}: #{payload[:message].to_s.truncate(80)}"
    bt = Array(payload[:backtrace]).join("\n")
    body_html = "<h4>#{ERB::Util.html_escape(payload[:message])}</h4><pre>#{ERB::Util.html_escape(bt)}</pre>"
    Messaging::EmailSender
      .send_email(
        subject,
        body: body_html,
        to: Array(payload[:to]).presence || env_recipients.presence || default_recipient,
        actor: nil,
        priority: :important,
        type: 'error_notification'
      )
      .set_source('system_activity', nil)
      .send(queue: queue_flag)
    Rails.logger.info("SafeNotifier: enqueued/sent system-break email for #{exception.class}")
  rescue StandardError => e
    Rails.logger.warn("SafeNotifier email delivery failed (#{e.class}): #{e.message}.")
    Rails.logger.error('SafeNotifier fallback suppressed; emails now persisted via Emails table')
  end

  def async_delivery?
    ENV.fetch('ERROR_NOTIFY_ASYNC', 'false') == 'true'
  end

  def env_recipients
    raw = ENV.fetch('ERROR_NOTIFY_TO', nil)
    return [] unless raw.present?

    raw.split(',').map(&:strip).reject(&:blank?)
  end

  def default_recipient
    rcpts = []
    rcpts << ENV['MAIL_FROM'] if ENV['MAIL_FROM'].present?
    rcpts << 'cspm@craftsilicon.com'
    rcpts << 'robert.mbugua@craftsilicon.com'
    rcpts.compact.uniq
  end

  def throttled?(payload)
    return false if defined?(Rails) && (Rails.env.development? || Rails.env.test?)

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

  def system_break?(context)
    ctx = context || {}
    return true if ctx.is_a?(Hash) && (ctx[:system_break] == true || ctx['system_break'] == true)

    # Optional global mode: only send in explicit break-only configuration
    (Rails.env.production? || Rails.env.staging?) && ENV.fetch('ERROR_NOTIFY_MODE', 'disabled') == 'break_only'
  end

  def fingerprint(payload)
    klass = payload[:exception_class]
    msg = payload[:message].to_s[0, 120]
    bt0 = Array(payload[:backtrace]).first.to_s
    Digest::SHA256.hexdigest([klass, msg, bt0].join('|'))
  end
end
