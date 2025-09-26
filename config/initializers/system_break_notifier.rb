if Rails.env.production? || Rails.env.staging?
  Rails.application.config.after_initialize do
    # Send a single email only when the Rails process exits due to an unhandled fatal error.
    # This relies on Rails/Unicorn/Puma setting $ERROR_INFO ($!) on fatal exceptions.
    at_exit do
      exc = $ERROR_INFO
      next unless exc

      # Ignore clean shutdowns
      if exc.is_a?(SystemExit)
        next if exc.status.to_i == 0
      end

      begin
        context = { system_break: true, pid: Process.pid, rails_env: Rails.env }
        ErrorLogger.log(exc, context: context)
        SafeNotifier.email(exc, context: context)
      rescue StandardError => e
        Rails.logger.error("system_break_notifier failed: #{e.class}: #{e.message}")
      end
    end
  end
end


