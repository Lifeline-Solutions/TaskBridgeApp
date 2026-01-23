class DashboardsController < ApplicationController
  before_action :authenticate_user!

  def index
    @teams = Team.all
    @stats = default_stats
    @ticket = Ticket.all
    @selected_team = nil
  end

  def fetch_stats
    team_name = params[:team_name]
    team = Team.find_by(name: team_name)

    if team
      session[:team_id] = team.id # Store the team ID in the session
      user_ids = team.users.pluck(:id)

      tickets_from_inception = Ticket.joins(:users, :statuses)
        .where(users: { id: user_ids })
        .where.not(statuses: { name: %w[Declined Closed Resolved] })
        .where('tickets.created_at <= ?', 30.days.ago)
        .distinct

      tickets_from_inception_count = tickets_from_inception.count

      tickets_from_inception_by_status = Status
        .left_outer_joins(tickets: [:users])
        .where('tickets.created_at <= ?', 30.days.ago)
        .where(users: { id: user_ids })
        .where.not(statuses: { name: %w[Declined Closed Resolved] })
        .group('statuses.name')
        .count

      # Calculate SLA breakdown for tickets from inception (using sla_target_response_deadline)
      # NO SLA: Use LEFT JOIN to catch tickets without SLA records OR with NO SLA explicitly marked
      tickets_from_inception_no_sla = tickets_from_inception
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: 'NO SLA' })
        .distinct
        .count

      tickets_from_inception_response_breached = tickets_from_inception
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
        .distinct
        .count

      tickets_from_inception_response_not_breached = tickets_from_inception
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: nil })
        .distinct
        .count

      tickets_from_inception_not_breached = tickets_from_inception
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: 'Not Breached' })
        .distinct
        .count

      tickets_last_30_days = Ticket.joins(:users, :statuses)
        .where(users: { id: user_ids })
        .where('tickets.created_at >= ?', 30.days.ago)

      total_tickets_last_30_days = tickets_last_30_days.count
      breached_tickets_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_status: 'Breached' })
        .count
      not_breached_tickets_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_status: ['Not Breached', nil] })
        .count
      # Breach Two
      response_breached_tickets_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_target_response_deadline: 'Breached' })
        .count
      response_breached_tickets_closed_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
        .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
        .where(sla_tickets: { sla_target_response_deadline: 'Breached' })
        .where(statuses: { name: %w[Closed Resolved] })
        .count
      response_breached_tickets_open_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
        .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
        .where(sla_tickets: { sla_target_response_deadline: 'Breached' })
        .where.not(statuses: { name: %w[Closed Resolved] })
        .count
      # Breach Three
      not_response_breached_tickets_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_target_response_deadline: ['Not Breached', nil] })
        .count
      resolution_breached_tickets_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
        .count
      # No SLA NO Breach
      no_sla_tickets_last_30_days = tickets_last_30_days
        .joins(:sla_tickets, :statuses)
        .where(sla_tickets: { sla_resolution_deadline: 'NO SLA' })
        .where.not(statuses: { name: %w[Closed Resolved Declined] })
        .count

      resolution_breached_open_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
        .joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
        .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
        .where.not(statuses: { name: %w[Closed Resolved Declined] })
        .count
      resolution_breached_closed_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
        .joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
        .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
        .where(statuses: { name: %w[Closed Resolved Declined] })
        .count
      not_resolution_breached_tickets_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: ['Not Breached', nil] })
        .count

      breached_tickets_per_assignee = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_target_response_deadline: 'Breached' })
        .group('users.first_name', 'users.last_name')
        .count

      breached_resolution_tickets_per_project = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_target_response_deadline: 'Breached' })
        .joins(:project)
        .group('projects.title')
        .count

      breached_tickets_resolved_per_assignee = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
        .group('users.first_name', 'users.last_name')
        .count

      breached_resolution_resolved_tickets_per_project = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
        .joins(:project)
        .group('projects.title')
        .count

      ticket_details = tickets_last_30_days.select(:issue, :subject, :created_at)

      stats = {
        total_tickets_last_30_days: total_tickets_last_30_days,
        no_sla_tickets_last_30_days: no_sla_tickets_last_30_days,
        breached_tickets_last_30_days: breached_tickets_last_30_days,
        not_breached_tickets_last_30_days: not_breached_tickets_last_30_days,
        response_breached_tickets_last_30_days: response_breached_tickets_last_30_days,
        response_breached_tickets_closed_last_30_days: response_breached_tickets_closed_last_30_days,
        response_breached_tickets_open_last_30_days: response_breached_tickets_open_last_30_days,
        not_response_breached_tickets_last_30_days: not_response_breached_tickets_last_30_days,
        resolution_breached_tickets_last_30_days: resolution_breached_tickets_last_30_days,
        resolution_breached_open_last_30_days: resolution_breached_open_last_30_days,
        resolution_breached_closed_last_30_days: resolution_breached_closed_last_30_days,
        not_resolution_breached_tickets_last_30_days: not_resolution_breached_tickets_last_30_days,
        breached_tickets_per_assignee: breached_tickets_per_assignee,
        breached_resolution_tickets_per_project: breached_resolution_tickets_per_project,
        breached_tickets_resolved_per_assignee: breached_tickets_resolved_per_assignee,
        breached_resolution_resolved_tickets_per_project: breached_resolution_resolved_tickets_per_project,
        ticket_details: ticket_details,
        # should not include 30 days
        tickets_from_inception_count: tickets_from_inception_count,
        tickets_from_inception_by_status: tickets_from_inception_by_status,
        tickets_from_inception_no_sla: tickets_from_inception_no_sla,
        tickets_from_inception_response_breached: tickets_from_inception_response_breached,
        tickets_from_inception_response_not_breached: tickets_from_inception_response_not_breached,
        tickets_from_inception_not_breached: tickets_from_inception_not_breached
      }

      render json: stats
    else
      render json: { error: 'Team not found' }, status: :not_found
    end
  end

  def tickets
    team = Team.find_by(id: session[:team_id])

    if team
      user_ids = team.users.pluck(:id)
      @tickets = Ticket.joins(:users)
        .where(users: { id: user_ids })
        .joins(:sla_tickets).joins(:statuses)

      type = params[:type]

      case type
      when 'initial_response_time_breached'
        @tickets = @tickets.where(sla_tickets: { sla_status: 'Breached' })
          .where('tickets.created_at >= ?', 30.days.ago)
      when 'initial_response_time_not_breached'
        @tickets = @tickets.where(sla_tickets: { sla_status: ['Not Breached', nil] })
          .where('tickets.created_at >= ?', 30.days.ago)
      when 'target_repair_time_breached'
        @tickets = @tickets.where(sla_tickets: { sla_target_response_deadline: 'Breached' })
          .where('tickets.created_at >= ?', 30.days.ago)
      when 'target_repair_time_breached_open'
        @tickets = @tickets.joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
          .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
          .where('tickets.created_at >= ?', 30.days.ago)
          .where(sla_tickets: { sla_target_response_deadline: 'Breached' })
          .where.not(statuses: { name: %w[Closed Resolved Declined] })

      when 'target_repair_time_breached_closed'
        @tickets = @tickets.joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
          .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
          .where('tickets.created_at >= ?', 30.days.ago).where(sla_tickets: { sla_target_response_deadline: 'Breached' })
          .where(statuses: { name: %w[Closed Resolved Declined] })

      when 'target_repair_time_not_breached'
        @tickets = @tickets.where(sla_tickets: { sla_target_response_deadline: ['Not Breached', nil] })
          .where('tickets.created_at >= ?', 30.days.ago)
      when 'target_resolution_time_breached'
        @tickets = @tickets.where(sla_tickets: { sla_resolution_deadline: 'Breached' })
          .where('tickets.created_at >= ?', 30.days.ago)
      when 'no_sla_population'
        @tickets = @tickets.where(sla_tickets: { sla_resolution_deadline: 'NO SLA' })
          .where('tickets.created_at >= ?', 30.days.ago)
          .where.not(statuses: { name: %w[Closed Resolved Declined] })

      when 'target_resolution_time_breached_open'
        @tickets = @tickets.joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
          .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
          .where('tickets.created_at >= ?', 30.days.ago)
          .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
          .where.not(statuses: { name: %w[Closed Resolved Declined] })
      when 'target_resolution_time_breached_closed'
        @tickets = @tickets.joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
          .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
          .where('tickets.created_at >= ?', 30.days.ago)
          .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
          .where.call(statuses: { name: %w[Closed Resolved Declined] })
      when 'target_resolution_time_not_breached'
        @tickets = @tickets.where(sla_tickets: { sla_resolution_deadline: ['Not Breached', nil] })
          .where('tickets.created_at >= ?', 30.days.ago)
        # === CHANGE START: show only selected status tickets when status param is present
      when 'tickets_from_inception_by_status'
        status_filter = params[:status]
        @tickets = if status_filter.present?
                     Ticket.joins(:statuses, :users)
                       .where(users: { id: user_ids })
                       .where(statuses: { name: status_filter })
                       .where.not(statuses: { name: %w[Declined Closed Resolved] })
                   else
                     Status.left_outer_joins(tickets: [:users])
                       .where(users: { id: user_ids })
                       .where.not(statuses: { name: %w[Declined Closed Resolved] })
                       .group('statuses.name')
                   end
        # === CHANGE END
      when 'tickets_from_inception_count'
        # Show all tickets from the team that are not closed, resolved or declined
        @tickets = Ticket.joins(:statuses, :users)
          .where(users: { id: user_ids })
          .where.not(statuses: { name: %w[Declined Closed Resolved] })

      when 'tickets_from_inception_no_sla'
        # Show tickets from inception with NO SLA for sla_target_response_deadline
        # Use LEFT JOIN to catch tickets without SLA records OR with NO SLA explicitly marked
        @tickets = Ticket.joins(:statuses, :users, :sla_tickets)
          .where(users: { id: user_ids })
          .where.not(statuses: { name: %w[Declined Closed Resolved] })
          .where(sla_tickets: { sla_resolution_deadline: 'NO SLA' })
          .distinct

      when 'tickets_from_inception_response_breached'
        # Show tickets from inception with Breached sla_target_response_deadline
        @tickets = Ticket.joins(:statuses, :users, :sla_tickets)
          .where(users: { id: user_ids })
          .where.not(statuses: { name: %w[Declined Closed Resolved] })
          .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
          .distinct

      when 'tickets_from_inception_response_not_breached'
        # Show tickets from inception with Not Breached sla_target_response_deadline
        @tickets = Ticket.joins(:statuses, :users, :sla_tickets)
          .where(users: { id: user_ids })
          .where.not(statuses: { name: %w[Declined Closed Resolved] })
          .where(sla_tickets: { sla_resolution_deadline: nil })
          .distinct

      when 'tickets_from_inception_not_breached'
        # Show tickets inceptions all not breached
        @ticket = Ticket.joins(:statuses, :users, :sla_tickets)
          .where(users: { id: user_ids })
          .where.not(statuses: { name: %w[Declined Closed Resolved] })
          .where(sla_tickets: { sla_resolution_deadline: 'Not Breached' })
          .distinct

      when 'total_tickets_last_30_days'
        # No additional filtering needed
        @tickets = @tickets.Ticket.joins(:statuses, :users)
          .where('tickets.created_at >= ?', 30.days.ago)
          .where(users: { id: user_ids })
          .where.not(statuses: { name: %w[Declined Closed Resolved] })
          .distinct
      end

      # Add ordering (latest first) and include a user team name (first team found) in the select
      @tickets = @tickets
        .joins(:taggings, :users)
        .joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
        .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
        .includes(:project)
        .select(
          'tickets.id', 'tickets.unique_id', 'tickets.priority', 'tickets.project_id',
          'tickets.issue', 'tickets.subject', 'tickets.created_at',
          'users.first_name', 'users.last_name',
          'statuses.name AS status_name',
          '(SELECT teams.name FROM teams INNER JOIN teams_users ON teams.id = teams_users.team_id WHERE teams_users.user_id = users.id LIMIT 1) AS user_team_name'
        )
        .order('tickets.created_at DESC')

      render json: @tickets.map { |ticket|
        ticket.as_json
          .merge(
            project_id: ticket.project_id,
            project_title: ticket.project&.title,
            user_name: "#{ticket.first_name} #{ticket.last_name}",
            user_team: ticket.respond_to?(:user_team_name) ? ticket.user_team_name : nil,
            status_name: ticket.status_name
          )
      }

    else
      render json: { error: 'Team not found' }, status: :not_found
    end
  end

  private

  def default_stats
    default_team = Team.find_by(name: 'Default Team')

    if default_team
      user_ids = default_team.users.pluck(:id)
      {
        total_tickets_last_30_days: Ticket.where(user_id: user_ids)..where(tickets: { created_at: 30.days.ago..Time.current }).count,
        tickets_from_inception: 0,
        tickets_from_inception_by_status: {},
        tickets_from_inception_no_sla: 0,
        tickets_from_inception_response_breached: 0,
        tickets_from_inception_response_not_breached: 0,
        tickets_from_inception_not_breached: 0
      }
    else
      {
        total_tickets_last_30_days: 0,
        tickets_from_inception: 0,
        tickets_from_inception_by_status: {},
        tickets_from_inception_no_sla: 0,
        tickets_from_inception_response_breached: 0,
        tickets_from_inception_response_not_breached: 0,
        tickets_from_inception_not_breached: 0
      }
    end
  end
end
