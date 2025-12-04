begin
  # ErrorNotifierMiddleware is auto-loaded by Rails from app/middleware directory
  # Only add it if the class is available
  if defined?(ErrorNotifierMiddleware)
    Rails.application.config.middleware.use ErrorNotifierMiddleware
  else
    Rails.logger.warn("ErrorNotifierMiddleware class not yet loaded, skipping middleware registration")
  end
rescue StandardError => e
  Rails.logger.warn("Error initializing ErrorNotifierMiddleware: #{e.class} - #{e.message}")
end

