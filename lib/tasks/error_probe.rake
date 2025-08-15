namespace :error do
  desc 'Trigger a test exception to exercise SafeNotifier and logging'
  task probe: :environment do
    raise 'ProbeError: simulated exception for error pipeline test'
  rescue StandardError => e
    SafeNotifier.email(e, context: { rake: 'error:probe', env: Rails.env })
    ErrorLogger.log(e, context: { rake: 'error:probe', env: Rails.env })
    puts 'Probe invoked. Check your inbox and log/production_errors.log.'
  end
end
