class SlaSummaryReportJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info "[SlaSummaryReportJob] Starting daily SLA summary report at #{Time.current}"

    # Get all teams or user groups that should receive reports
    teams = Team.all

    teams.find_each do |team|
      send_summary_to_team(team)
    end

    Rails.logger.info "[SlaSummaryReportJob] Completed daily SLA summary report at #{Time.current}"
  end

  private

  def send_summary_to_team(team)
    user_ids = team.users.pluck(:id)
    return if user_ids.empty?

    # Collect SLA summary data for team's tickets
    summary_data = build_summary_data(user_ids)

    # Get recipients (team leads, HODs, project managers)
    recipients = collect_report_recipients(team)
    return if recipients.empty?

    # Send individual reports to each recipient
    # DISABLED: SLA automation emails
    # recipients.each do |recipient|
    #   send_summary_email(recipient, summary_data, team)
    # end
  end

  def build_summary_data(user_ids)
    base_scope = Ticket.joins(:users, :sla_ticket)
                       .where(users: { id: user_ids })
                       .where('tickets.created_at >= ?', 1.day.ago)

    {
      total_tickets: base_scope.distinct.count,
      breached_count: count_breached_tickets(base_scope),
      on_time_count: count_on_time_tickets(base_scope),
      at_risk_count: count_at_risk_tickets(user_ids),
      breach_by_type: breach_breakdown(base_scope),
      breach_by_severity: severity_breakdown(base_scope),
      at_risk_tickets: get_at_risk_tickets(user_ids),
      performance_metrics: calculate_performance_metrics(base_scope)
    }
  end

  def count_breached_tickets(scope)
    scope.where(sla_tickets: { sla_status: 'Breached' })
         .or(scope.where(sla_tickets: { sla_target_response_deadline: 'Breached' }))
         .or(scope.where(sla_tickets: { sla_resolution_deadline: 'Breached' }))
         .distinct
         .count
  end

  def count_on_time_tickets(scope)
    scope.where(sla_tickets: { sla_status: 'Not Breached' })
         .where(sla_tickets: { sla_target_response_deadline: 'Not Breached' })
         .where(sla_tickets: { sla_resolution_deadline: 'Not Breached' })
         .distinct
         .count
  end

  def count_at_risk_tickets(user_ids)
    # Tickets approaching SLA deadline (within next 2 hours)
    threshold = 2.hours.from_now

    Ticket.joins(:users, :sla_ticket)
          .where(users: { id: user_ids })
          .where(
            '(tickets.initial_response_deadline BETWEEN ? AND ?) OR '\
            '(tickets.target_repair_deadline BETWEEN ? AND ?) OR '\
            '(tickets.resolution_deadline BETWEEN ? AND ?)',
            Time.current, threshold,
            Time.current, threshold,
            Time.current, threshold
          )
          .where(sla_tickets: { sla_status: 'Not Breached' })
          .distinct
          .count
  end

  def breach_breakdown(scope)
    {
      initial_response: scope.where(sla_tickets: { sla_status: 'Breached' }).distinct.count,
      target_repair: scope.where(sla_tickets: { sla_target_response_deadline: 'Breached' }).distinct.count,
      resolution: scope.where(sla_tickets: { sla_resolution_deadline: 'Breached' }).distinct.count
    }
  end

  def severity_breakdown(scope)
    scope.joins(:sla_ticket)
         .where.not(sla_tickets: { sla_status: 'Not Breached' })
         .group(:priority)
         .count
  end

  def get_at_risk_tickets(user_ids)
    threshold = 2.hours.from_now

    Ticket.joins(:users, :sla_ticket, :project)
          .where(users: { id: user_ids })
          .where(
            '(tickets.initial_response_deadline BETWEEN ? AND ?) OR '\
            '(tickets.target_repair_deadline BETWEEN ? AND ?) OR '\
            '(tickets.resolution_deadline BETWEEN ? AND ?)',
            Time.current, threshold,
            Time.current, threshold,
            Time.current, threshold
          )
          .where(sla_tickets: { sla_status: 'Not Breached' })
          .select('tickets.*, projects.title as project_title')
          .distinct
          .limit(10)
  end

  def calculate_performance_metrics(scope)
    total = scope.distinct.count
    return { compliance_rate: 0 } if total.zero?

    on_time = count_on_time_tickets(scope)
    compliance_rate = ((on_time.to_f / total) * 100).round(2)

    {
      compliance_rate: compliance_rate,
      total_evaluated: total
    }
  end

  def collect_report_recipients(team)
    recipients = []

    # Add HODs (Head of Department)
    hods = team.users.select { |u| u.has_role?(:hod) }
    recipients += hods.map(&:email)

    # Add project managers
    project_managers = team.users.joins(:roles).where(roles: { name: 'project manager' }).distinct
    recipients += project_managers.pluck(:email)

    recipients.uniq.compact.reject(&:blank?)
  end

  def send_summary_email(recipient_email, summary_data, team)
    # Create a user object or use email string
    user = User.find_by(email: recipient_email)

    Messaging::EmailSender
      .send_email(
        "Daily SLA Summary Report - #{team.name}",
        to: [recipient_email],
        actor: nil,
        priority: :normal,
        type: 'sla_daily_summary'
      )
      .use_template(
        view: 'user_mailer/sla_daily_summary',
        assigns: {
          user: user,
          summary_data: summary_data,
          team: team,
          report_date: Date.today
        },
        layout: nil
      )
      .set_source('team', team.id)
      .send(queue: true)

    Rails.logger.info "[SlaSummaryReportJob] Sent daily SLA summary to #{recipient_email}"
  rescue StandardError => e
    Rails.logger.error "[SlaSummaryReportJob] Failed to send summary to #{recipient_email}: #{e.message}"
  end
end
