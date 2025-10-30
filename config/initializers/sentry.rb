Sentry.init do |config|
  config.dsn = 'https://484d650cacbee29caf07c89e2909f74b@o4507601057808384.ingest.de.sentry.io/4510276676485200'
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Add data like request headers and IP for users,
  # see https://docs.sentry.io/platforms/ruby/data-management/data-collected/ for more info
  config.send_default_pii = true
end