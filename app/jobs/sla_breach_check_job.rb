class SlaBreachCheckJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[SlaBreachCheckJob] Starting SLA breach check at #{Time.current}"

    check_initial_response_sla
    check_target_repair_sla
    check_resolution_sla

    Rails.logger.info "[SlaBreachCheckJob] Completed SLA breach check at #{Time.current}"
  end

  private

  def check_initial_response_sla
    # Find tickets where initial response deadline has passed
    # and SLA status has not been marked as breached yet
    tickets = Ticket.joins(:sla_ticket)
                    .where('tickets.initial_response_deadline < ?', Time.current)
                    .where.not(sla_tickets: { sla_status: 'Breached' })
                    .where('tickets.initial_response_deadline IS NOT NULL')

    Rails.logger.info "[SlaBreachCheckJob] Found #{tickets.count} tickets with initial response SLA breach"

    tickets.find_each do |ticket|
      sla_ticket = ticket.sla_ticket
      next unless sla_ticket

      # Update SLA status
      sla_ticket.update(sla_status: 'Breached')

      # Send notification to stakeholders
      notify_stakeholders(ticket, :initial_response_breach)

      Rails.logger.info "[SlaBreachCheckJob] Marked ticket #{ticket.unique_id} as breached (Initial Response)"
    end
  end

  def check_target_repair_sla
    # Find tickets where target repair deadline has passed
    tickets = Ticket.joins(:sla_ticket)
                    .where('tickets.target_repair_deadline < ?', Time.current)
                    .where.not(sla_tickets: { sla_target_response_deadline: 'Breached' })
                    .where('tickets.target_repair_deadline IS NOT NULL')

    Rails.logger.info "[SlaBreachCheckJob] Found #{tickets.count} tickets with target repair SLA breach"

    tickets.find_each do |ticket|
      sla_ticket = ticket.sla_ticket
      next unless sla_ticket

      # Update SLA target response deadline status
      sla_ticket.update(sla_target_response_deadline: 'Breached')

      # Send notification to stakeholders
      notify_stakeholders(ticket, :target_repair_breach)

      Rails.logger.info "[SlaBreachCheckJob] Marked ticket #{ticket.unique_id} as breached (Target Repair)"
    end
  end

  def check_resolution_sla
    # Find tickets where resolution deadline has passed
    tickets = Ticket.joins(:sla_ticket)
                    .where('tickets.resolution_deadline < ?', Time.current)
                    .where.not(sla_tickets: { sla_resolution_deadline: 'Breached' })
                    .where('tickets.resolution_deadline IS NOT NULL')

    Rails.logger.info "[SlaBreachCheckJob] Found #{tickets.count} tickets with resolution SLA breach"

    tickets.find_each do |ticket|
      sla_ticket = ticket.sla_ticket
      next unless sla_ticket

      # Update SLA resolution deadline status
      sla_ticket.update(sla_resolution_deadline: 'Breached')

      # Send notification to stakeholders
      notify_stakeholders(ticket, :resolution_breach)

      Rails.logger.info "[SlaBreachCheckJob] Marked ticket #{ticket.unique_id} as breached (Resolution)"
    end
  end

  def notify_stakeholders(ticket, breach_type)
    # Get recipient emails
    recipients = collect_recipients(ticket)
    return if recipients.empty?

    # Send email notification using Messaging::EmailSender
    Messaging::EmailSender
      .send_email(
        breach_subject(ticket, breach_type),
        to: recipients,
        actor: nil,
        priority: :important,
        type: 'sla_breach_notification'
      )
      .use_template(
        view: 'user_mailer/sla_breach_notification',
        assigns: { ticket: ticket, breach_type: breach_type },
        layout: nil
      )
      .set_source('ticket', ticket.id)
      .send(queue: true)

    Rails.logger.info "[SlaBreachCheckJob] Sent #{breach_type} notification for ticket #{ticket.unique_id} to #{recipients.join(', ')}"
  rescue StandardError => e
    Rails.logger.error "[SlaBreachCheckJob] Failed to send notification for ticket #{ticket.unique_id}: #{e.message}"
  end

  def collect_recipients(ticket)
    recipients = []

    # Add project manager
    project = ticket.project
    if project
      # Get project managers from the project
      project_managers = project.users.joins(:roles).where(roles: { name: 'project manager' }).distinct
      recipients += project_managers.pluck(:email)
    end

    # Add assigned users (tagged users)
    assigned_users = ticket.users.pluck(:email)
    recipients += assigned_users

    # Add ticket creator
    recipients << ticket.user.email if ticket.user&.email

    # Remove duplicates and blank emails
    recipients.uniq.compact.reject(&:blank?)
  end

  def breach_subject(ticket, breach_type)
    type_label = case breach_type
                 when :initial_response_breach
                   'Initial Response'
                 when :target_repair_breach
                   'Target Repair'
                 when :resolution_breach
                   'Resolution'
                 else
                   'SLA'
                 end

    "[SLA BREACH] #{type_label} SLA Breached - Ticket #{ticket.unique_id}"
  end
end
