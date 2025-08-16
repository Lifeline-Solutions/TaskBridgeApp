# Capture Sidekiq server-side job errors and report via SafeNotifier
if defined?(Sidekiq)
  Sidekiq.configure_server do |config|
    config.error_handlers << proc do |ex, ctx|
      begin
        job = ctx[:job] || {}
        # Avoid loops if the failing job is our own email dispatcher
        if job['class'] == 'EmailDispatchJob'
          next
        end

        context = {
          sidekiq: true,
          queue: job['queue'],
          job_class: job['class'],
          wrapped: job['wrapped'],
          jid: job['jid'],
          args: job['args'],
          retry: job['retry'],
          failed_at: Time.now.iso8601
        }

        # Log and notify via our persisted email pipeline
        ErrorLogger.log(ex, context: context) if defined?(ErrorLogger)
        SafeNotifier.email(ex, context: context)
      rescue => inner
        Rails.logger.error("Sidekiq error handler failed: #{inner.class}: #{inner.message}")
      end
    end
  end
end
