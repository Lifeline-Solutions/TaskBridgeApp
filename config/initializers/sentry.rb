# frozen_string_literal: true

# Only initialize Sentry when a DSN is provided.
dsn = ENV["SENTRY_DSN"].presence
if dsn
  Sentry.init do |config|
    config.dsn = dsn
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]

    # Keep tracing minimal by default; override via env if desired
    config.traces_sample_rate = (ENV["SENTRY_TRACES_SAMPLE_RATE"] || 0.0).to_f
    config.profiles_sample_rate = (ENV["SENTRY_PROFILES_SAMPLE_RATE"] || 0.0).to_f
  end
end