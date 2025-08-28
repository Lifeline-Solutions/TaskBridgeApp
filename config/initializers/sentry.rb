Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN'] # Only initializes if ENV is set
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  config.send_default_pii = true
end if ENV['SENTRY_DSN'].present?