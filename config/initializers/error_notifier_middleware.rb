# Explicitly load the ErrorNotifierMiddleware before inserting it into the stack
# This ensures the class is available during asset precompilation in production
require Rails.root.join('app/middleware/error_notifier_middleware')

# Insert the middleware at the beginning of the stack
Rails.application.config.middleware.insert_before 0, ErrorNotifierMiddleware