namespace :error do
  desc 'Trigger a test exception to exercise SafeNotifier and logging'
  task probe: :environment do
    raise 'ProbeError: simulated exception for error pipeline test'
  rescue StandardError => e
    ErrorLogger.log(e, context: { rake: 'error:probe', env: Rails.env })
    puts 'Probe invoked. Check log/production_errors.log.'
  end
end
