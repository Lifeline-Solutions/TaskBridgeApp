# config/environments/staging.rb
require "active_support/core_ext/integer/time"
require_relative "production"

Rails.application.configure do
  # prod-like behavior
  config.enable_reloading = false
  config.eager_load = true
  config.cache_classes = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # assets & static
  config.assets.compile = false
  config.assets.digest = true
  # config.public_file_server.enabled = true  # uncomment if Rails must serve /public

  # storage
  config.active_storage.service = :staging

  # logging
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "debug")
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))

  # jobs
  config.active_job.queue_adapter = :sidekiq
  config.active_job.queue_name_prefix = "cspm_staging"

 # mailer
config.action_mailer.perform_caching = false
config.action_mailer.raise_delivery_errors = true
config.action_mailer.perform_deliveries = true
config.action_mailer.default_url_options = {
  host: ENV.fetch("APP_HOST", "172.16.2.15"),
  protocol: ENV.fetch("APP_PROTOCOL", "http")
}
config.action_mailer.delivery_method = :smtp

if ENV["SMTP_USERNAME"].present? && ENV["SMTP_PASSWORD"].present?
  config.action_mailer.smtp_settings = {
    address:              ENV.fetch("SMTP_ADDRESS", "secure.emailsrvr.com"),
    port:                 ENV.fetch("SMTP_PORT", "465").to_i,
    domain:               ENV.fetch("SMTP_DOMAIN", "craftsilicon.com"),
    user_name:            ENV["SMTP_USERNAME"],
    password:             ENV["SMTP_PASSWORD"],
    authentication:       :plain,
    ssl:                  true,
    enable_starttls_auto: false,
    openssl_verify_mode:  ENV.fetch("SMTP_OPENSSL_VERIFY_MODE", "none"),
    open_timeout:         30,
    read_timeout:         30
  }
end
end