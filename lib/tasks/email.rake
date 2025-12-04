namespace :email do
  desc 'Check email delivery status and retry failed jobs'
  task check_delivery: :environment do
    puts '=' * 80
    puts 'EMAIL DELIVERY STATUS CHECK'
    puts '=' * 80
    puts ''

    stats = Sidekiq::Stats.new
    retry_set = Sidekiq::RetrySet.new
    dead_set = Sidekiq::DeadSet.new

    puts 'Overall Sidekiq Stats:'
    puts "  Processed: #{stats.processed}"
    puts "  Failed: #{stats.failed}"
    puts "  Retry queue size: #{retry_set.size}"
    puts "  Dead queue size: #{dead_set.size}"
    puts ''

    # Check for email-specific failures
    email_retries = retry_set.select { |job| job.klass == 'ActionMailer::MailDeliveryJob' || job['wrapped'] == 'ActionMailer::MailDeliveryJob' }
    email_dead = dead_set.select { |job| job.klass == 'ActionMailer::MailDeliveryJob' || job['wrapped'] == 'ActionMailer::MailDeliveryJob' }

    puts 'Email Job Status:'
    puts "  Email jobs in retry queue: #{email_retries.count}"
    puts "  Email jobs in dead queue: #{email_dead.count}"
    puts ''

    if email_retries.any?
      puts 'Recent Email Retry Errors:'
      email_retries.first(10).each do |job|
        puts "  - Job ID: #{job.jid}"
        puts "    Error: #{job.item['error_class']}: #{job.item['error_message']}"
        puts "    Retry count: #{job.item['retry_count']}"
        puts "    Next retry: #{job.at}"
        puts ''
      end
    end

    if email_dead.any?
      puts 'Dead Email Jobs (need manual intervention):'
      email_dead.first(5).each do |job|
        puts "  - Job ID: #{job.jid}"
        puts "    Error: #{job.item['error_class']}: #{job.item['error_message']}"
        puts "    Failed at: #{job.at}"
        puts ''
      end
    end

    # Check for SMTP connection errors specifically
    smtp_errors = retry_set.select do |job|
      (job.klass == 'ActionMailer::MailDeliveryJob' || job['wrapped'] == 'ActionMailer::MailDeliveryJob') &&
        job.item['error_message'] =~ /not accepting connections|SMTPFatalError|OpenTimeout/i
    end

    if smtp_errors.any?
      puts "⚠️  WARNING: #{smtp_errors.count} email jobs failing due to SMTP connection issues"
      puts '   These will retry automatically with exponential backoff'
      puts "   Most recent error: #{smtp_errors.first.item['error_message']}"
      puts ''
    end

    puts '=' * 80
  end

  desc 'Retry all failed email jobs immediately'
  task retry_all: :environment do
    puts 'Retrying all failed email jobs...'

    retry_set = Sidekiq::RetrySet.new
    email_retries = retry_set.select { |job| job.klass == 'ActionMailer::MailDeliveryJob' || job['wrapped'] == 'ActionMailer::MailDeliveryJob' }

    count = 0
    email_retries.each do |job|
      job.retry
      count += 1
    end

    puts "✓ Retried #{count} email jobs"
  end

  desc 'Clear dead email jobs (use with caution)'
  task clear_dead: :environment do
    dead_set = Sidekiq::DeadSet.new
    email_dead = dead_set.select { |job| job.klass == 'ActionMailer::MailDeliveryJob' || job['wrapped'] == 'ActionMailer::MailDeliveryJob' }

    puts "Found #{email_dead.count} dead email jobs"
    puts 'Are you sure you want to delete these? (y/N)'

    if $stdin.gets.chomp.downcase == 'y'
      count = 0
      email_dead.each do |job|
        job.delete
        count += 1
      end
      puts "✓ Deleted #{count} dead email jobs"
    else
      puts 'Cancelled'
    end
  end

  desc 'Test SMTP connection'
  task test_smtp: :environment do
    puts 'Testing SMTP connection...'
    puts '=' * 80

    smtp_settings = ActionMailer::Base.smtp_settings

    puts 'SMTP Configuration:'
    puts "  Address: #{smtp_settings[:address]}"
    puts "  Port: #{smtp_settings[:port]}"
    puts "  Domain: #{smtp_settings[:domain]}"
    puts "  Username: #{smtp_settings[:user_name]}"
    puts "  SSL: #{smtp_settings[:ssl]}"
    puts "  Open Timeout: #{smtp_settings[:open_timeout]}s"
    puts "  Read Timeout: #{smtp_settings[:read_timeout]}s"
    puts ''

    begin
      puts 'Attempting connection...'
      require 'net/smtp'

      smtp = Net::SMTP.new(smtp_settings[:address], smtp_settings[:port])
      smtp.enable_ssl if smtp_settings[:ssl]
      smtp.open_timeout = smtp_settings[:open_timeout]
      smtp.read_timeout = smtp_settings[:read_timeout]

      smtp.start(smtp_settings[:domain], smtp_settings[:user_name], smtp_settings[:password], smtp_settings[:authentication]) do |s|
        puts '✓ Successfully connected to SMTP server!'
        puts "  Server capabilities: #{'CRAM-MD5 ' if s.capable_cram_md5_auth?}#{'LOGIN ' if s.capable_login_auth?}#{'PLAIN' if s.capable_plain_auth?}"
      end
    rescue Net::SMTPFatalError => e
      puts "✗ SMTP Fatal Error: #{e.message}"
      puts '  This usually means the server is temporarily refusing connections'
      puts '  Email jobs will retry automatically'
    rescue Net::OpenTimeout => e
      puts "✗ Connection Timeout: #{e.message}"
      puts "  The server is not responding within #{smtp_settings[:open_timeout]} seconds"
    rescue StandardError => e
      puts "✗ Error: #{e.class} - #{e.message}"
    end

    puts '=' * 80
  end

  desc 'Show email delivery statistics for last 24 hours'
  task stats: :environment do
    puts '=' * 80
    puts 'EMAIL DELIVERY STATISTICS (Last 24 hours)'
    puts '=' * 80
    puts ''

    # Get stats from Sidekiq history if available
    stats = Sidekiq::Stats.new
    Sidekiq::Stats::History.new(1) # Last day

    puts 'Overall Stats:'
    puts "  Total processed: #{stats.processed}"
    puts "  Total failed: #{stats.failed}"
    puts "  Success rate: #{stats.processed.positive? ? ((stats.processed - stats.failed).to_f / stats.processed * 100).round(2) : 0}%"
    puts ''

    # Estimate email jobs (this is approximate)
    retry_set = Sidekiq::RetrySet.new
    dead_set = Sidekiq::DeadSet.new

    email_retries = retry_set.select { |job| job.klass == 'ActionMailer::MailDeliveryJob' || job['wrapped'] == 'ActionMailer::MailDeliveryJob' }
    email_dead = dead_set.select { |job| job.klass == 'ActionMailer::MailDeliveryJob' || job['wrapped'] == 'ActionMailer::MailDeliveryJob' }

    puts 'Current Email Queue Status:'
    puts "  Retrying: #{email_retries.count}"
    puts "  Dead: #{email_dead.count}"
    puts ''

    # Error breakdown
    error_types = Hash.new(0)
    email_retries.each do |job|
      error_class = job.item['error_class'] || 'Unknown'
      error_types[error_class] += 1
    end

    if error_types.any?
      puts 'Error Types in Retry Queue:'
      error_types.sort_by { |_k, v| -v }.each do |error, count|
        puts "  #{error}: #{count}"
      end
    end

    puts '=' * 80
  end
end
