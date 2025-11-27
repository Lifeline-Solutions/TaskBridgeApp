# config/initializers/error_notifier_middleware.rb
# Initialize error notifier middleware to capture application-wide errors

Rails.application.config.middleware.use ErrorNotifierMiddleware

