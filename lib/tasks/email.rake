namespace :email do
  desc 'Dispatch queued emails (use in cron)'
  task dispatch: :environment do
    ids = Email.where(status: 'queued').order(:created_at).limit(1000).pluck(:id)
    puts "Dispatching #{ids.size} queued emails..."
    ids.each { |id| EmailDispatchJob.perform_later(id) }
  end

  desc 'Retry failed emails updated within last 24h'
  task retry_failed: :environment do
    ids = Email.where(status: 'failed').where('updated_at > ?', 24.hours.ago).pluck(:id)
    puts "Retrying #{ids.size} failed emails..."
    ids.each { |id| EmailDispatchJob.perform_later(id) }
  end
end
