class ApplicationJob < ActiveJob::Base
  rescue_from(StandardError) do |exception|
    context = { job: self.class.name, args: arguments, queue: queue_name }
    ErrorLogger.log(exception, context: context)
    SafeNotifier.email(exception, context: context)
    raise
  end
end
