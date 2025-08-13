# frozen_string_literal: true


Sentry.init do |config|
  config.dsn = 'https://ce8148f2726e2a100ceb92cd399d53e7@o4509803352489984.ingest.us.sentry.io/4509803353800704'
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Set traces_sample_rate to 1.0 to capture 100%
  # of transactions for tracing.
  # We recommend adjusting this value in production.
  config.traces_sample_rate = 1.0
  # or
  config.traces_sampler = lambda do |context|
    true
  end
  # Set profiles_sample_rate to profile 100%
  # of sampled transactions.
  # We recommend adjusting this value in production.
  config.profiles_sample_rate = 1.0
end