require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # In the development environment your application's code is reloaded any time
  # it changes. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.enable_reloading = true

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing
  config.server_timing = true

  # Enable/disable caching. By default caching is disabled.
  # Run rails dev:cache to toggle caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.action_controller.perform_caching = true
    config.action_controller.enable_fragment_cache_logging = true

    config.cache_store = :memory_store
    config.public_file_server.headers = {
      "Cache-Control" => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  config.action_mailer.perform_caching = false

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise exceptions for disallowed deprecations.
  config.active_support.disallowed_deprecation = :raise

  # Tell Active Support which deprecation messages to disallow.
  config.active_support.disallowed_deprecation_warnings = []

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Highlight code that enqueued background job in logs.
  config.active_job.verbose_enqueue_logs = true

  config.active_job.queue_adapter = :sidekiq


  # Suppress logger output for asset requests.
  config.assets.quiet = true



  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Uncomment if you wish to allow Action Cable access from any origin.
  # config.action_cable.disable_request_forgery_protection = true

  # Raise error when a before_action's only/except options reference missing actions

  config.action_mailer.default_url_options = { host: ENV.fetch('APP_HOST', '172.16.2.15'), protocol: ENV.fetch('APP_PROTOCOL', 'http') }
  config.action_controller.raise_on_missing_callback_actions = true
  config.active_storage.variant_processor = :mini_magick
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :smtp
  
  smtp_address = ENV.fetch('SMTP_ADDRESS', 'secure.emailsrvr.com')
  smtp_port    = Integer(ENV.fetch('SMTP_PORT', '465'))
  smtp_domain  = ENV.fetch('SMTP_DOMAIN', 'craftsilicon.com')
  smtp_user    = ENV.fetch('SMTP_USERNAME', 'taskbridgestaging@craftsilicon.com')
  smtp_pass    = ENV['SMTP_PASSWORD']  # Must be set in environment
  
  # Port 465 uses implicit SSL (ssl: true, tls: false)
  # Port 587 uses explicit TLS (ssl: false, tls: true, enable_starttls_auto: true)
  
  if smtp_port == 465
    # Implicit SSL for port 465
    use_ssl = true
    use_tls = false
    enable_starttls = false
  elsif smtp_port == 587
    # Explicit TLS/STARTTLS for port 587
    use_ssl = false
    use_tls = true
    enable_starttls = true
  else
    # Custom configuration via ENV vars
    use_ssl = ENV.fetch('SMTP_USE_SSL', 'false') == 'true'
    use_tls = ENV.fetch('SMTP_USE_TLS', 'true') == 'true'
    enable_starttls = ENV.fetch('SMTP_ENABLE_STARTTLS_AUTO', 'false') == 'true'
  end
  
  config.action_mailer.smtp_settings = {
    address: smtp_address,
    port: smtp_port,
    domain: smtp_domain,
    user_name: smtp_user,
    password: smtp_pass,
    authentication: :plain,
    ssl: use_ssl,
    tls: use_tls,
    enable_starttls_auto: enable_starttls,
    open_timeout: Integer(ENV.fetch('SMTP_OPEN_TIMEOUT', '10')),
    read_timeout: Integer(ENV.fetch('SMTP_READ_TIMEOUT', '10'))
  }.tap do |h|
    # Only disable verification if explicitly asked (not recommended)
    if ENV['SMTP_OPENSSL_VERIFY_MODE'].present?
      h[:openssl_verify_mode] = ENV['SMTP_OPENSSL_VERIFY_MODE']
    end
    
    # Log SMTP settings (excluding password) for debugging
    Rails.logger.info("STAGING SMTP Configuration: address=#{smtp_address}, port=#{smtp_port}, user=#{smtp_user.present? ? '[SET]' : '[MISSING]'}, password=#{smtp_pass.present? ? '[SET]' : '[MISSING]'}, ssl=#{use_ssl}, tls=#{use_tls}")
  end
end
