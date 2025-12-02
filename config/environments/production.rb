require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Ensures that a master key has been made available in ENV["RAILS_MASTER_KEY"], config/master.key, or an environment
  # key such as config/credentials/production.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Disable serving static files from `public/`, relying on NGINX/Apache to do so instead.
  # config.public_file_server.enabled = false

  # Compress CSS using a preprocessor.
  # config.assets.css_compressor = :sass

  # Do not fall back to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :production

  # Mount Action Cable outside main process or domain.
  # config.action_cable.mount_path = nil
  # config.action_cable.url = "wss://example.com/cable"
  # config.action_cable.allowed_request_origins = [ "http://example.com", /http:\/\/example.*/ ]

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # Can be used together with config.force_ssl for Strict-Transport-Security and secure cookies.
  # config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Log to STDOUT by default
  config.logger = ActiveSupport::Logger.new(STDOUT)
                                       .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
                                       .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # Prepend all log lines with the following tags.
  config.log_tags = [ :request_id ]

  # "info" includes generic and useful information about system operation, but avoids logging too much
  # information to avoid inadvertent exposure of personally identifiable information (PII). If you
  # want to log everything, set the level to "debug".
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Use a real queuing backend for Active Job (and separate queues per environment).
  config.active_job.queue_adapter = :sidekiq
  # config.active_job.queue_name_prefix = "cspm_production"

  config.action_mailer.perform_caching = false

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Raise error when a before_action's only/except options reference missing actions

  config.action_mailer.default_url_options = { host: 'https://taskbridge.craftsilicon.com/', protocol: 'https' }
  config.action_controller.raise_on_missing_callback_actions = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :smtp

  # SMTP Configuration with improved reliability
  # If server refuses connections (554 error), Sidekiq will automatically retry with exponential backoff
  # NOTE: Credentials MUST NOT be stored in source. Rotate the exposed account password immediately
  # and place secrets into environment variables or Rails credentials.
  # Prefer using port 587 (STARTTLS) where possible. If you must use port 465 (implicit SSL), set
  # SMTP_PORT=465 and SMTP_USE_SSL=true in your environment and the settings will adapt.
  smtp_use_ssl = ENV.fetch('SMTP_USE_SSL', 'false').downcase == 'true'

  # Recommended: use STARTTLS (port 587) with enable_starttls_auto: true
  # Fallback: implicit SSL (port 465) when SMTP_USE_SSL=true
  # Load credentials from ENV first, then Rails encrypted credentials as a fallback
  smtp_address = ENV.fetch('SMTP_ADDRESS', Rails.application.credentials.dig(:smtp, :address) || 'secure.emailsrvr.com')
  smtp_port = ENV.fetch('SMTP_PORT', (smtp_use_ssl ? '465' : '587')).to_i
  smtp_domain = ENV.fetch('SMTP_DOMAIN', Rails.application.credentials.dig(:smtp, :domain) || 'craftsilicon.com')
  smtp_username = ENV['SMTP_USERNAME'].presence || Rails.application.credentials.dig(:smtp, :user) || 'cspm@craftsilicon.com'
  smtp_password = ENV['SMTP_PASSWORD'].presence || Rails.application.credentials.dig(:smtp, :password)
  smtp_auth_method = (ENV['SMTP_AUTH_METHOD'] || Rails.application.credentials.dig(:smtp, :auth_method) || 'login').to_s

  if smtp_password.blank?
    # Raise a runtime warning so deploy/ops teams notice immediately in logs
    warn "[SMTP-WARN] SMTP_PASSWORD is not set in ENV and no credentials found. Mail delivery will fail with authentication errors."
  end

  # Convert to symbol safely
  begin
    auth_sym = smtp_auth_method.to_sym
  rescue StandardError
    auth_sym = :login
  end

  config.action_mailer.smtp_settings = {
    address: smtp_address,
    port: smtp_port,
    domain: smtp_domain,
    user_name: smtp_username,
    password: smtp_password,
    authentication: auth_sym,
    enable_starttls_auto: !smtp_use_ssl, # use STARTTLS when not using implicit SSL
    ssl: smtp_use_ssl,
    # It's unsafe to disable certificate verification in production. If your provider/reason
    # requires skipping verification temporarily, set SMTP_OPENSSL_VERIFY_MODE in the env.
    openssl_verify_mode: ENV.fetch('SMTP_OPENSSL_VERIFY_MODE', 'peer'),
    open_timeout: ENV.fetch('SMTP_OPEN_TIMEOUT', '60').to_i,
    read_timeout: ENV.fetch('SMTP_READ_TIMEOUT', '60').to_i
  }

  # Quick runtime validation (does not send email) - enable in console for testing only:
  # ruby -r net/smtp -e "puts Net::SMTP.start(ENV['SMTP_ADDRESS'], ENV['SMTP_PORT'].to_i) { |smtp| smtp.start(ENV['SMTP_DOMAIN'], ENV['SMTP_USERNAME'], ENV['SMTP_PASSWORD'], ENV['SMTP_AUTH_METHOD'] || 'login'); puts 'OK' }"
  # IMPORTANT: If you have leaked the SMTP password in git, rotate it with the provider immediately.
end