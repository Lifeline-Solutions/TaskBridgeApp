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
    host: ENV.fetch("APP_HOST", "172.16.2.15"), # host ONLY
    protocol: "http"
  }
  config.action_mailer.delivery_method = :smtp

  # Choose ONE of the two blocks below:

  # --- If using implicit TLS on 465 ---
  config.action_mailer.smtp_settings = {
    address:              ENV.fetch("SMTP_ADDRESS", "secure.emailsrvr.com"),
    port:                 ENV.fetch("SMTP_PORT", "465").to_i,
    domain:               ENV.fetch("SMTP_DOMAIN", "craftsilicon.com"),
    # user_name:            ENV.fetch("SMTP_USERNAME"),
    # password:             ENV.fetch("SMTP_PASSWORD"),
    authentication:       :plain,
    ssl:                  true,
    enable_starttls_auto: false,
    openssl_verify_mode:  ENV.fetch("SMTP_OPENSSL_VERIFY_MODE", "none"),
    open_timeout:         30,
    read_timeout:         30
  }

  # --- If using STARTTLS on 587 (use this instead, and remove the block above) ---
  # config.action_mailer.smtp_settings = {
  #   address:              ENV.fetch("SMTP_ADDRESS", "secure.emailsrvr.com"),
  #   port:                 ENV.fetch("SMTP_PORT", "587").to_i,
  #   domain:               ENV.fetch("SMTP_DOMAIN", "craftsilicon.com"),
  #   user_name:            ENV.fetch("SMTP_USERNAME"),
  #   password:             ENV.fetch("SMTP_PASSWORD"),
  #   authentication:       :plain,
  #   enable_starttls_auto: true,
  #   open_timeout:         30,
  #   read_timeout:         30
  # }

  # security / SSL
  config.force_ssl = false
  # config.assume_ssl = true # if behind SSL-terminating proxy but you access via http internally

  # allowed hosts (NO scheme)
  config.hosts << ENV.fetch("APP_HOST", "172.16.2.15")
  config.ssl_options = { redirect: false, hsts: false }
  config.middleware.delete ActionDispatch::SSL rescue nil
  # config.hosts << /.*\.craftsilicon\.com/

  # i18n / deprecations / schema dumps
  config.i18n.fallbacks = true
  config.active_support.report_deprecations = false
  config.active_record.dump_schema_after_migration = false
end 

