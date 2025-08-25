class DashboardsController < ApplicationController
  before_action :authenticate_user!

  def index
    @teams = Team.all
    @stats = default_stats
    @ticket = Ticket.all
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
        .distinct

      tickets_from_inception_count = tickets_from_inception.count

      tickets_from_inception_by_status = Status
        .left_outer_joins(tickets: [:users])
        .where(users: { id: user_ids })
        .where.not(statuses: { name: %w[Declined Closed Resolved] })
        .group('statuses.name')
        .count

      tickets_last_30_days = Ticket.joins(:users)
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
      not_response_breached_tickets_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_target_response_deadline: ['Not Breached', nil] })
        .count
      resolution_breached_tickets_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
        .count
      no_sla_tickets_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: 'NO SLA' })
        .count
      resolution_breached_open_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
        .joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
        .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
        .where.not(statuses: { name: %w[Closed Resolved] })
        .count
      resolution_breached_closed_last_30_days = tickets_last_30_days
        .joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
        .joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
        .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
        .where(statuses: { name: %w[Closed Resolved] })
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
        tickets_from_inception_count: tickets_from_inception_count,
        tickets_from_inception_by_status: tickets_from_inception_by_status

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
        .where('tickets.created_at >= ?', 30.days.ago)
        .joins(:sla_tickets)

      type = params[:type]

      case type
      when 'initial_response_time_breached'
        @tickets = @tickets.where(sla_tickets: { sla_status: 'Breached' })
      when 'initial_response_time_not_breached'
        @tickets = @tickets.where(sla_tickets: { sla_status: ['Not Breached', nil] })
      when 'target_repair_time_breached'
        @tickets = @tickets.where(sla_tickets: { sla_target_response_deadline: 'Breached' })
      when 'target_repair_time_breached_open'
        @tickets = @tickets.joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
          .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
          .where(sla_tickets: { sla_target_response_deadline: 'Breached' })
          .where.not(statuses: { name: %w[Closed Resolved] })
      when 'target_repair_time_breached_closed'
        @tickets = @tickets.joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
          .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
          .where(sla_tickets: { sla_target_response_deadline: 'Breached' })
          .where(statuses: { name: %w[Closed Resolved] })
      when 'target_repair_time_not_breached'
        @tickets = @tickets.where(sla_tickets: { sla_target_response_deadline: ['Not Breached', nil] })
      when 'target_resolution_time_breached'
        @tickets = @tickets.where(sla_tickets: { sla_resolution_deadline: 'Breached' })
      when 'no_sla_population'
        @tickets = @tickets.where(sla_tickets: { sla_resolution_deadline: 'NO SLA' })
      when 'target_resolution_time_breached_open'
        @tickets = @tickets.joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
          .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
          .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
          .where.not(statuses: { name: %w[Closed Resolved] })
      when 'target_resolution_time_breached_closed'
        @tickets = @tickets.joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
          .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
          .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
          .where(statuses: { name: %w[Closed Resolved] })
      when 'target_resolution_time_not_breached'
        @tickets = @tickets.where(sla_tickets: { sla_resolution_deadline: ['Not Breached', nil] })
      when 'tickets_from_inception_by_status'
        @tickets = Status.left_outer_joins(tickets: [:users]).where(users: { id: user_ids }).where.not(statuses: { name: %w[Declined Closed Resolved] }).group('statuses.name')
      when 'tickets_from_inception_count'
        # Show all tickets from the team that are not closed, resolved or declined
        @tickets = Ticket.joins(:statuses, :users, :taggings)
          .where(users: { id: user_ids })
          .where.not(statuses: { name: %w[Declined Closed Resolved] })
      when 'total_tickets_last_30_days'
        # No additional filtering needed
      end

      @tickets = @tickets
        .joins(:taggings, :users)
        .joins('LEFT JOIN add_statuses ON add_statuses.ticket_id = tickets.id')
        .joins('LEFT JOIN statuses ON statuses.id = add_statuses.status_id')
        .includes(:project)
        .select(
          'tickets.id', 'tickets.unique_id', 'tickets.priority', 'tickets.project_id',
          'tickets.issue', 'tickets.subject', 'tickets.created_at',
          'users.first_name', 'users.last_name',
          'statuses.name AS status_name'
        )

      render json: @tickets.map { |ticket|
        ticket.as_json
          .merge(
            project_id: ticket.project_id,
            project_title: ticket.project&.title,
            user_name: "#{ticket.first_name} #{ticket.last_name}",
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
        total_tickets_last_30_days: Ticket.where(user_id: user_ids).where('created_at >= ?', 30.days.ago).count,
        tickets_from_inception: 0,
        tickets_from_inception_by_status: {}
      }
    else
      {
        total_tickets_last_30_days: 0,
        tickets_from_inception: 0,
        tickets_from_inception_by_status: {}
      }
    end
  end
end
