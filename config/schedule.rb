# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Example:
#
# set :output, "/path/to/my/cron_log.log"
#
# every 2.hours do
#   command "/usr/bin/some_great_command"
#   runner "MyModel.some_method"
#   rake "some:great:rake:task"
# end
#
# every 4.days do
#   runner "AnotherModel.prune_old_records"
# end

# Learn more: http://github.com/javan/whenever

# Use this file to easily define all of your cron jobs.
set :output, "log/cron.log"
set :environment, 'production'

every 1.day, at: '12:01 am' do
  runner "DailyReportJob.perform_later"
end

# For development (uncomment if you want to test locally)
set :environment, 'development'
every 1.day, at: '18:20 pm' do
  runner "DailyReportJob.perform_later"
end

# ========================================
# SLA Monitoring Jobs
# ========================================

# Check for SLA breaches every 15 minutes during business hours
# This helps catch breaches quickly and update the database
every 15.minutes do
  runner "SlaBreachCheckJob.perform_later"
end

# Send warning notifications every 30 minutes
# Provides proactive alerts before SLA deadlines are missed
every 30.minutes do
  runner "SlaWarningJob.perform_later"
end

# Daily SLA summary report at 8:00 AM
# Sends comprehensive performance metrics to team leads and management
every 1.day, at: '8:00 am' do
  runner "SlaSummaryReportJob.perform_later"
end
