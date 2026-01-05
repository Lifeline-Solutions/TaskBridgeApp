class SlaWarningJob < ApplicationJob
  queue_as :default

  # Warning thresholds in minutes
  WARNING_THRESHOLDS = [30, 60, 120].freeze

  def perform
    Rails.logger.info "[SlaWarningJob] Starting SLA warning check at #{Time.current}"

    check_initial_response_warnings
    check_target_repair_warnings
    check_resolution_warnings

    Rails.logger.info "[SlaWarningJob] Completed SLA warning check at #{Time.current}"
  end

  private

  def check_initial_response_warnings
    WARNING_THRESHOLDS.each do |threshold_minutes|
      threshold_time = Time.current + threshold_minutes.minutes

      # Find tickets approaching initial response deadline
      # CRITICAL: Only process open tickets (exclude Closed, Resolved, Declined)
      tickets = Ticket.joins(:sla_ticket)
        .joins(:statuses)
        .where.not(statuses: { name: %w[Closed Resolved Declined] })
        .where('tickets.initial_response_deadline BETWEEN ? AND ?',
               Time.current, threshold_time)
        .where(sla_tickets: { sla_status: 'Not Breached' })
        .where('tickets.initial_response_deadline IS NOT NULL')
        .distinct

      tickets.find_each do |ticket|
        calculate_time_remaining(ticket.initial_response_deadline)
        next if already_warned?(ticket, :initial_response, threshold_minutes)

        # DISABLED: SLA automation emails
        # send_warning_notification(ticket, :initial_response, time_remaining)
        mark_as_warned(ticket, :initial_response, threshold_minutes)
      end
    end
  end

  def check_target_repair_warnings
    WARNING_THRESHOLDS.each do |threshold_minutes|
      threshold_time = Time.current + threshold_minutes.minutes

      # CRITICAL: Only process open tickets (exclude Closed, Resolved, Declined)
      tickets = Ticket.joins(:sla_ticket)
        .joins(:statuses)
        .where.not(statuses: { name: %w[Closed Resolved Declined] })
        .where('tickets.target_repair_deadline BETWEEN ? AND ?',
               Time.current, threshold_time)
        .where(sla_tickets: { sla_target_response_deadline: 'Not Breached' })
        .where('tickets.target_repair_deadline IS NOT NULL')
        .distinct

      tickets.find_each do |ticket|
        calculate_time_remaining(ticket.target_repair_deadline)
        next if already_warned?(ticket, :target_repair, threshold_minutes)

        # DISABLED: SLA automation emails
        # send_warning_notification(ticket, :target_repair, time_remaining)
        mark_as_warned(ticket, :target_repair, threshold_minutes)
      end
    end
  end

  def check_resolution_warnings
    WARNING_THRESHOLDS.each do |threshold_minutes|
      threshold_time = Time.current + threshold_minutes.minutes

      # CRITICAL: Only process open tickets (exclude Closed, Resolved, Declined)
      tickets = Ticket.joins(:sla_ticket)
        .joins(:statuses)
        .where.not(statuses: { name: %w[Closed Resolved Declined] })
        .where('tickets.resolution_deadline BETWEEN ? AND ?',
               Time.current, threshold_time)
        .where(sla_tickets: { sla_resolution_deadline: 'Not Breached' })
        .where('tickets.resolution_deadline IS NOT NULL')
        .distinct

      tickets.find_each do |ticket|
        calculate_time_remaining(ticket.resolution_deadline)
        next if already_warned?(ticket, :resolution, threshold_minutes)

        # DISABLED: SLA automation emails
        # send_warning_notification(ticket, :resolution, time_remaining)
        mark_as_warned(ticket, :resolution, threshold_minutes)
      end
    end
  end

  def send_warning_notification(ticket, sla_type, time_remaining)
    recipients = collect_recipients(ticket)
    return if recipients.empty?

    Messaging::EmailSender
      .send_email(
        warning_subject(ticket, sla_type, time_remaining),
        to: recipients,
        actor: nil,
        priority: :important,
        type: 'sla_warning_notification'
      )
      .use_template(
        view: 'user_mailer/sla_warning_notification',
        assigns: {
          ticket: ticket,
          sla_type: sla_type,
          time_remaining: time_remaining
        },
        layout: nil
      )
      .set_source('ticket', ticket.id)
      .send(queue: true)

    Rails.logger.info "[SlaWarningJob] Sent #{sla_type} warning for ticket #{ticket.unique_id} (#{time_remaining} remaining)"
  rescue StandardError => e
    Rails.logger.error "[SlaWarningJob] Failed to send warning for ticket #{ticket.unique_id}: #{e.message}"
  end

  def collect_recipients(ticket)
    recipients = []

    project = ticket.project
    if project
      project_managers = project.users.joins(:roles).where(roles: { name: 'project manager' }).distinct
      recipients += project_managers.pluck(:email)
    end

    assigned_users = ticket.users.pluck(:email)
    recipients += assigned_users

    recipients << ticket.user.email if ticket.user&.email

    recipients.uniq.compact.reject(&:blank?)
  end

  def calculate_time_remaining(deadline)
    return 'Unknown' unless deadline

    seconds = (deadline - Time.current).to_i
    return '0 minutes' if seconds <= 0

    hours = seconds / 3600
    minutes = (seconds % 3600) / 60

    if hours.positive?
      "#{hours} hour#{'s' if hours > 1} #{minutes} minute#{'s' if minutes != 1}"
    else
      "#{minutes} minute#{'s' if minutes != 1}"
    end
  end

  def warning_subject(ticket, sla_type, time_remaining)
    type_label = case sla_type
                 when :initial_response
                   'Initial Response'
                 when :target_repair
                   'Target Repair'
                 when :resolution
                   'Resolution'
                 else
                   'SLA'
                 end

    "[SLA WARNING] #{type_label} SLA expires in #{time_remaining} - Ticket #{ticket.unique_id}"
  end

  def already_warned?(ticket, sla_type, threshold)
    # Use Rails cache to track warnings (expires after 24 hours)
    cache_key = "sla_warning:#{ticket.id}:#{sla_type}:#{threshold}"
    Rails.cache.exist?(cache_key)
  end

  def mark_as_warned(ticket, sla_type, threshold)
    cache_key = "sla_warning:#{ticket.id}:#{sla_type}:#{threshold}"
    # Cache for 24 hours
    Rails.cache.write(cache_key, true, expires_in: 24.hours)
  end
end
