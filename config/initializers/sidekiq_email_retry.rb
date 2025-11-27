# Custom Sidekiq retry configuration for email delivery jobs
# This handles temporary SMTP errors like "554 not accepting connections"

Sidekiq.configure_server do |config|
  # Custom retry logic for ActionMailer jobs
  config.death_handlers << lambda do |job, ex|
    # Log when email jobs are moved to dead queue
    if job['wrapped'] == 'ActionMailer::MailDeliveryJob'
      Rails.logger.error("Email job #{job['jid']} moved to dead queue after #{job['retry_count']} retries")
      Rails.logger.error("Error: #{ex.class} - #{ex.message}")
      Rails.logger.error("Job args: #{job['args'].inspect}")

      # Optionally send notification to admin
      # AdminMailer.job_failed_notification(job, ex).deliver_later if Rails.env.production?
    end
  end

  # Custom error handler for SMTP errors
  config.error_handlers << lambda do |ex, ctx_hash|
    if ex.is_a?(Net::SMTPFatalError) && ex.message.include?('not accepting connections')
      Rails.logger.warn("SMTP server refusing connections - job will retry automatically")
      Rails.logger.warn("Job: #{ctx_hash[:job]}")

      # Don't re-raise, let Sidekiq handle retry
      # This prevents immediate failure and allows retry with backoff
    end
  end
end

# Configure retry backoff for ActionMailer jobs
# This provides exponential backoff with jitter for email delivery
Sidekiq.configure_client do |config|
  # Client config if needed
end

# Custom retry middleware for email jobs
class EmailRetryMiddleware
  def call(worker, job, queue)
    yield
  rescue Net::SMTPFatalError => e
    if e.message.include?('not accepting connections')
      # Log but allow Sidekiq to retry
      Rails.logger.warn("SMTP connection refused (#{e.message}), will retry with backoff")
      raise # Let Sidekiq handle the retry
    else
      # Other SMTP errors should also retry
      Rails.logger.error("SMTP error: #{e.class} - #{e.message}")
      raise
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
    # Network-related errors should retry
    Rails.logger.warn("Network error sending email: #{e.class} - #{e.message}, will retry")
    raise
  end
end

# Add middleware to Sidekiq server
Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add EmailRetryMiddleware
  end
end

