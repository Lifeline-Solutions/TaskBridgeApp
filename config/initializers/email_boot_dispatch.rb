# Re-enqueue any queued emails on boot to protect against queue loss
if ENV.fetch('EMAIL_DISPATCH_ON_BOOT', 'true') == 'true'
  Rails.application.config.to_prepare do
    begin
      Email.where(status: 'queued').limit(500).pluck(:id).each do |id|
        EmailDispatchJob.perform_later(id)
      end
    rescue => e
      Rails.logger.warn("Email boot dispatch skipped: #{e.class}: #{e.message}")
    end
  end
end
