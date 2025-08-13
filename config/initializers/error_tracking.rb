Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe("process_action.action_controller") do |_name, _start, _finish, _id, payload|
    exception = payload[:exception_object]
    next unless exception

    context = {
      controller: payload[:controller],
      action:     payload[:action],
      params:     (payload[:params] || {}).except("controller", "action"),
      format:     payload[:format],
      method:     payload[:method],
      path:       payload[:path]
    }

    ErrorLogger.log(exception, context: context)
    SafeNotifier.email(exception, context: context)   # now sends a payload
  end
end