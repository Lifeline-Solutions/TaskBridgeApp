# Rotate production_errors.log weekly to prevent unbounded growth
Rails.application.config.after_initialize do
  log_path = Rails.root.join('log', 'production_errors.log')
  begin
    if File.exist?(log_path) && File.size(log_path) > Integer(ENV.fetch('ERROR_LOG_MAX_BYTES', '5242880'))
      timestamp = Time.now.utc.strftime('%Y%m%d%H%M%S')
      rotated = Rails.root.join('log', "production_errors-#{timestamp}.log")
      File.rename(log_path, rotated)
      FileUtils.touch(log_path)
    end
  rescue => e
    Rails.logger.warn("Error log rotation failed: #{e.class}: #{e.message}")
  end
end
