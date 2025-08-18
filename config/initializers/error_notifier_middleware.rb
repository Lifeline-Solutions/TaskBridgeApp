# ErrorNotifierMiddleware is inserted from config/application.rb
# This initializer remains only to ensure the class is loaded in some boots.
require Rails.root.join('app/middleware/error_notifier_middleware')