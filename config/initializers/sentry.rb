# frozen_string_literal: true

# Only initialize Sentry when a DSN is provided.
Sentry.init do |config|
  config.dsn = 'https://2c85eaaa604d06def24a5250f6595b55@o4507601057808384.ingest.de.sentry.io/4509908884783184'
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Add data like request headers and IP for users,
  # see https://docs.sentry.io/platforms/ruby/data-management/data-collected/ for more info
  config.send_default_pii = true
end