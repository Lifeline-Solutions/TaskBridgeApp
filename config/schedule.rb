# Use this file to easily define all of your cron jobs.
# Learn more: http://github.com/javan/whenever

# Set output log file
set :output, "log/cron.log"

# Environment will be set by Capistrano's whenever_environment
# In development/local testing, it uses RAILS_ENV or defaults to 'production'
set :environment, ENV.fetch('RAILS_ENV', 'production')


every 1.day, at: '12:01 am' do
  runner "DailyReportJob.perform_later"
end

# Check for SLA breaches every 15 minutes
# Detects tickets that have passed their SLA deadlines
every 2.hours do
  runner "SlaBreachCheckJob.perform_later"
end

# Send warning notifications every 30 minutes
# Alerts users before SLA deadlines are missed (at 30, 60, 120 min thresholds)
every 30.minutes do
  runner "SlaWarningJob.perform_later"
end

# Daily SLA summary report at 8:00 AM
# Sends comprehensive SLA performance metrics to team leads
every 1.day, at: '8:00 am' do
  runner "SlaSummaryReportJob.perform_later"
end
