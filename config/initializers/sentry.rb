Sentry.init do |config|
  config.dsn = 'https://2b9c965db519d3094b523ceb32145cc2@o4507601057808384.ingest.de.sentry.io/4510278476759120'
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Add data like request headers and IP for users,
  # see https://docs.sentry.io/platforms/ruby/data-management/data-collected/ for more info
  config.send_default_pii = true
end