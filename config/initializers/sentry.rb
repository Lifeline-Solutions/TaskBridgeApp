Sentry.init do |config|
  config.dsn = 'https://30e370340976cf8c95c0bbd2c4ae2ee8@o4507601057808384.ingest.de.sentry.io/4509908898480208'
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Add data like request headers and IP for users,
  # see https://docs.sentry.io/platforms/ruby/data-management/data-collected/ for more info
  config.send_default_pii = true
end