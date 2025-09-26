require 'csv'
require 'axlsx'
class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def profiles_show
    authorize! :generate, :report

    @users = []
    @tickets = Ticket.none
    @events = []
    @issues = []
    @status_counts = {}
    @tickets_by_client = {}
    @assigned_at_by_ticket_id = {}
    @all_ticket_events_by_ticket = {}
    @total_hold_times = {}

    return respond_to(&:html) unless params[:user_id].present? || params[:start_date].present? || params[:end_date].present?

    @users = User.where(id: params[:user_id])
    @selected_user = @users.first

    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : nil
    end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : nil
    from_time = start_date&.beginning_of_day
    to_time = end_date&.end_of_day

    assignment_events_scope = Event.where('events.details ILIKE ?', '%was assigned to the ticket%')

    if @selected_user.present?
      display_name = [@selected_user.first_name, @selected_user.last_name].compact.join(' ').strip
      if display_name.present?
        escaped = ActiveRecord::Base.sanitize_sql_like(display_name)
        assignment_events_scope = assignment_events_scope.where(
          'events.details ILIKE ? OR events.details ILIKE ?',
          "%#{escaped} was assigned to the ticket%",
          "%#{escaped}was assigned to the ticket%"
        )
      end
    end

    if from_time || to_time
      from_time ||= Time.at(0)
      to_time ||= Time.current
      assignment_events_scope = assignment_events_scope.where(created_at: from_time..to_time)
    end

    ticket_ids = assignment_events_scope.where.not(ticket_id: nil).distinct.pluck(:ticket_id)
    @assignment_events = assignment_events_scope.includes(:ticket)
    @assigned_at_by_ticket_id = @assignment_events
      .group_by(&:ticket_id)
      .transform_values { |evs| evs.min_by(&:created_at)&.created_at }

    @all_ticket_events_by_ticket = Event
      .where(ticket_id: ticket_ids)
      .select(:ticket_id, :details, :created_at)
      .group_by(&:ticket_id)

    @tickets = Ticket.where(id: ticket_ids)
      .includes({ project: :client }, :events, :issues, :statuses, :sla_tickets)
      .distinct

    filtered_tickets = @tickets
    @status_counts = filtered_tickets
      .group_by { |ticket| ticket.statuses.first&.name || 'N/A' }
      .transform_values(&:count)

    @tickets_by_client = filtered_tickets
      .group_by { |ticket| ticket.project&.client&.name || 'Unknown Client' }

    @events = @assignment_events.to_a

    @issues = Issue.where(ticket_id: ticket_ids)
    @issues = @issues.where(created_at: from_time..to_time) if from_time || to_time
    @issues = @issues.includes(:ticket).to_a

    durations = []
    @tickets.each do |t|
      a = assigned_at_for(t)
      r = resolved_at_for(t)
      durations << (r - a).to_i if a && r
    end
    @avg_assignment_to_resolved_count = durations.size
    if durations.any?
      avg_seconds = (durations.sum / durations.size.to_f).round
      @avg_assignment_to_resolved_seconds = avg_seconds
      @avg_assignment_to_resolved_human = helpers.distance_of_time_in_words(Time.at(0), Time.at(avg_seconds), include_seconds: true)
    else
      @avg_assignment_to_resolved_seconds = nil
      @avg_assignment_to_resolved_human = nil
    end

    # Calculate total hold times
    @total_hold_times = {}
    @ticket_hold_time_total_seconds = {}
    @tickets.each do |ticket|
      hold_periods = []
      events = Event.where(ticket_id: ticket.id).order(:created_at).to_a
      assignments = events.select { |e| e.details&.include?('was assigned to the ticket') }
      handovers = events.select { |e| e.details&.include?('was handed over') }

      # Determine the display name for the selected user (to match event text)
      selected_name = ([@selected_user.first_name, @selected_user.last_name].compact.join(' ').strip if @selected_user.present?)

      # Only consider assignments where the selected user was assigned
      if selected_name.present?
        assignments_for_user = assignments.select do |e|
          parse_assignment_details(e.details)[:assigned_to].to_s == selected_name
        end
        # Handovers explicitly involving the selected user (fallback to substring match)
        handovers_for_user = handovers.select { |h| h.details.to_s.include?(selected_name) }

        assignments_for_user.each do |assign_event|
          assigned_at = assign_event.created_at
          # Earliest of the next assignment (anyone), next handover involving selected user,
          # or when the ticket entered a terminal state (Resolved/Closed/Declined)
          next_assignment = assignments.find { |a| a.created_at > assign_event.created_at }
          next_handover = handovers_for_user.find { |h| h.created_at > assign_event.created_at }
          terminal_time = terminal_state_time_for(ticket)
          candidate_end_times = [next_assignment&.created_at, next_handover&.created_at, terminal_time]
                                  .compact
                                  .select { |t| t > assigned_at }
          end_time = candidate_end_times.min || Time.current
          hold_periods << (end_time - assigned_at)
        end
      end

      @total_hold_times[ticket.id] = hold_periods
      @ticket_hold_time_total_seconds[ticket.id] = hold_periods.sum
    end

    respond_to do |format|
      format.html
      format.csv { send_data generate_user_csv(@users), filename: "#{@selected_user.first_name}_#{@selected_user.last_name}_#{Date.today}.csv" }
    end
  end

  helper_method :parse_assignment_details, :assigned_at_for, :resolved_at_for, :resolution_duration_for, :format_full_duration

  # Formats total seconds as a human string with years, months, days, hours, minutes, and seconds
  def format_full_duration(total_seconds)
    seconds = total_seconds.to_i
    return '0 seconds' if seconds <= 0

    parts = ActiveSupport::Duration.build(seconds).parts # e.g., {years:, months:, days:, hours:, minutes:, seconds:}
    order = [:years, :months, :days, :hours, :minutes, :seconds]

    order.map do |key|
      value = parts[key].to_i
      value.positive? ? "#{value} #{key.to_s.singularize}#{'s' if value != 1}" : nil
    end.compact.join(' ')
  end

  def profiles_show_user
    if params[:user_id] && params[:client_name]
      @user = User.find(params[:user_id])
      start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : nil
      end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : nil

      @tickets = @user.tickets.joins(project: :client)
        .where(clients: { name: params[:client_name] })
      @tickets = @tickets.where('tickets.created_at >= ?', start_date) if start_date
      @tickets = @tickets.where('tickets.created_at <= ?', end_date) if end_date

      if params[:status].present?
        case params[:status].downcase
        when 'open'
          @tickets = @tickets.joins(:statuses).where.not(statuses: { name: %w[Closed Resolved Declined] })
        when 'closed'
          @tickets = @tickets.joins(:statuses).where(statuses: { name: %w[Closed Resolved] })
        end
      end
    else
      @tickets = Ticket.none
      flash[:alert] = 'Please provide a valid user and client.'
      render :show
    end
  end

  private

  # Parse "Assigned To", "SLA Status", "Target Response Deadline" from details text
  # Example: "#{user.first_name} #{user.last_name}was assigned to the ticket, with Status:  #{sla_ticket.sla_status} and Target Response Deadline #{sla_target_response_deadline}"
  def parse_assignment_details(details)
    return { assigned_to: nil, sla_status: nil, target_deadline: nil } if details.blank?

    normalized = details.to_s.gsub('was assigned', ' was assigned')

    assigned_to = normalized[/\A\s*(.+?)\s+was assigned to the ticket/i, 1]&.strip
    sla_status = normalized[/Status:\s*([^,]+)/i, 1]&.strip
    target_deadline = normalized[/Target Response Deadline\s*(.+)\z/i, 1]&.strip

    { assigned_to: assigned_to, sla_status: sla_status, target_deadline: target_deadline }
  end

  # First assignment timestamp for the selected user on this ticket
  def assigned_at_for(ticket)
    return nil unless ticket&.id

    @assigned_at_by_ticket_id&.[](ticket.id)
  end

  # Best-effort detection of when a ticket changed status to "Resolved"
  # 1) ticket.resolved_at or ticket.closed_at if present
  # 2) First event whose details indicate "Resolved"
  def resolved_at_for(ticket)
    return nil unless ticket

    return ticket.resolved_at if ticket.respond_to?(:resolved_at) && ticket.resolved_at.present?
    return ticket.closed_at if ticket.respond_to?(:closed_at) && ticket.closed_at.present?

    events = @all_ticket_events_by_ticket&.[](ticket.id) || []
    events.sort_by!(&:created_at)

    resolved_event = events.find do |e|
      d = e.details.to_s.downcase
      d.include?('resolved') && (
        d.include?('status') ||
          d.include?('status changed') ||
          d.include?('changed status') ||
          d.include?('to resolved')
      )
    end

    resolved_event&.created_at
  end

  # Returns a hash describing the time taken to reach Resolved.
  # Prefer duration from assignment to resolved; fall back to ticket.created_at if no assignment found.
  # { from: Time, to: Time, seconds: Integer, human: "x days y hours ..." }
  def resolution_duration_for(ticket)
    return nil unless ticket

    to_time = resolved_at_for(ticket)
    return nil unless to_time

    from_time = assigned_at_for(ticket) || ticket.created_at
    return nil unless from_time

    seconds = (to_time - from_time).to_i
    human = helpers.distance_of_time_in_words(from_time, to_time, include_seconds: true)

    { from: from_time, to: to_time, seconds: seconds, human: human }
  end

  def generate_user_csv(users)
    CSV.generate(headers: true) do |csv|
      csv << ['User Name', 'Project Name', 'Ticket Subject', 'Ticket Status', 'SLA Status', 'SLA Target Response Deadline',
              'SLA Repair Time Deadline', 'SLA Resolution Time Deadline', 'Created At']
      users.each do |user|
        user.tickets.each do |ticket|
          sla_ticket = SlaTicket.find_by(ticket_id: ticket.id)
          csv << [
            user.name,
            ticket.project.title,
            ticket.unique_id.gsub('–', '-'),
            ticket.subject,
            ticket.statuses.first&.name || 'N/A',
            sla_ticket&.sla_target_response_deadline || 'N/A',
            sla_ticket&.sla_resolution_deadline || 'N/A',
            ticket.created_at.strftime('%d/%b/%Y %I:%M:%S %p')
          ]
        end
      end
    end
  end

  # Returns the earliest timestamp when the ticket enters a terminal state
  # Terminal states considered: Resolved, Closed, Declined
  def terminal_state_time_for(ticket)
    return nil unless ticket

    # Prefer any explicit resolved/closed timestamps on the ticket first
    times = []
    times << ticket.resolved_at if ticket.respond_to?(:resolved_at) && ticket.resolved_at.present?
    times << ticket.closed_at if ticket.respond_to?(:closed_at) && ticket.closed_at.present?

    # Also look into events for resolved/closed/declined
    events = @all_ticket_events_by_ticket&.[](ticket.id) || []
    events.sort_by!(&:created_at)

    events.each do |e|
      d = e.details.to_s.downcase
      if d.include?('resolved') && (d.include?('status') || d.include?('status changed') || d.include?('changed status') || d.include?('to resolved'))
        times << e.created_at
      end
      if d.include?('closed') && (d.include?('status') || d.include?('status changed') || d.include?('changed status') || d.include?('to closed'))
        times << e.created_at
      end
      if d.include?('declined') && (d.include?('status') || d.include?('status changed') || d.include?('changed status') || d.include?('to declined'))
        times << e.created_at
      end
    end

    times.compact.min
  end
end
