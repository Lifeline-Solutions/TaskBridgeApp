require Rails.root.join('app/middleware/error_notifier_middleware')

Rails.application.config.middleware.insert_before 0, ErrorNotifierMiddleware