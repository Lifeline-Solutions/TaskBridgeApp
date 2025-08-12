# config/initializers/error_tracking.rb
Rails.application.config.after_initialize do
  # ---- Web Request Errors ----
  ActiveSupport::Notifications.subscribe("process_action.action_controller") do |_name, _start, _finish, _id, payload|
    exception = payload[:exception_object]

    if exception
      context = {
        controller: payload[:controller],
        action: payload[:action],
        params: payload[:params].except("controller", "action"),
        format: payload[:format],
        method: payload[:method],
        path: payload[:path]
      }

      ErrorLogger.log(exception, context: context)
      ErrorNotifierMailer.notify_error(exception, context: context).deliver_later
    end
  end

  # ---- Sidekiq Job Errors ----
  if defined?(Sidekiq)
    Sidekiq.configure_server do |config|
      config.error_handlers << proc do |exception, context_hash|
        context = {
          job_class: context_hash['class'],
          args: context_hash['args'],
          queue: context_hash['queue']
        }

        ErrorLogger.log(exception, context: context)
        ErrorNotifierMailer.notify_error(exception, context: context).deliver_later
      end
    end
  end
end
