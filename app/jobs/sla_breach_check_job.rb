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

    tickets.find_each do |ticket|
      sla_ticket = ticket.sla_ticket
      next unless sla_ticket

      # Update SLA status
      sla_ticket.update(sla_status: 'Breached')

      # Send notification to stakeholders
      notify_stakeholders(ticket, :initial_response_breach)
    end
  end

  def check_target_repair_sla
    # Find tickets where target repair deadline has passed
    tickets = Ticket.joins(:sla_ticket)
                    .where('tickets.target_repair_deadline < ?', Time.current)
                    .where.not(sla_tickets: { sla_target_response_deadline: 'Breached' })
                    .where('tickets.target_repair_deadline IS NOT NULL')

    tickets.find_each do |ticket|
      sla_ticket = ticket.sla_ticket
      next unless sla_ticket

      # Update SLA target response deadline status
      sla_ticket.update(sla_target_response_deadline: 'Breached')

      # Send notification to stakeholders
      notify_stakeholders(ticket, :target_repair_breach)
    end
  end

  def check_resolution_sla
    # Find tickets where resolution deadline has passed
    tickets = Ticket.joins(:sla_ticket)
                    .where('tickets.resolution_deadline < ?', Time.current)
                    .where.not(sla_tickets: { sla_resolution_deadline: 'Breached' })
                    .where('tickets.resolution_deadline IS NOT NULL')

    tickets.find_each do |ticket|
      sla_ticket = ticket.sla_ticket
      next unless sla_ticket

      # Update SLA resolution deadline status
      sla_ticket.update(sla_resolution_deadline: 'Breached')

      # Send notification to stakeholders
      notify_stakeholders(ticket, :resolution_breach)
    end
  end

  def notify_stakeholders(ticket, breach_type)
    recipients = collect_recipients(ticket)
    to_list = recipients[:to]
    cc_list = recipients[:cc]
    return if to_list.empty? && cc_list.empty?

    Messaging::EmailSender
      .send_email(
        breach_subject(ticket, breach_type),
        to: to_list,
        cc: cc_list,
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
  end

  def collect_recipients(ticket)
    # Primary recipients: assigned users excluding client/ceo roles
    assigned_users_scope = ticket.users.joins(:roles)
    primary_scope = assigned_users_scope.where.not(roles: { name: %w[client ceo] }).distinct
    to_emails = primary_scope.pluck(:email).compact.reject(&:blank?)

    # CC: HODs tagged on the ticket, HODs on the project, and the project owner/user (if any), all excluding client/ceo
    hod_role_scope = User.joins(:roles).where(roles: { name: 'hod' })

    ticket_hod_emails = assigned_users_scope.merge(hod_role_scope).pluck(:email)
    project_hod_emails = if ticket.project
                           ticket.project.users.merge(hod_role_scope).pluck(:email)
                         else
                           []
                         end

    project_owner_email = ticket.project&.user&.email
    cc_emails = (ticket_hod_emails + project_hod_emails)
    cc_emails << project_owner_email if project_owner_email.present?

    # Finalize cc list by excluding client/ceo roles and removing blanks/duplicates
    cc_emails = User.where(email: cc_emails.compact.uniq)
                    .joins(:roles)
                    .where.not(roles: { name: %w[client ceo] })
                    .pluck(:email)

    { to: to_emails.uniq, cc: cc_emails.uniq }
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
