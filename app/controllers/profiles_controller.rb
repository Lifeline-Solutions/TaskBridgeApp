require 'csv'
require 'axlsx'
require 'set'
class ProfilesController < ApplicationController
  before_action :authenticate_user!
  def project_report
    authorize! :generate, :report

    if params[:team_id].present?
      @team = Team.find(params[:team_id])
      @team_members = @team.users
      user_ids = @team_members.pluck(:id)

      # Handle custom date range or default to last 6 months
      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
      else
        start_date = 6.months.ago.to_date
        end_date = Date.today
      end

      @tickets = Ticket.joins(:statuses, :project, :taggings)
        .where('tickets.created_at >= ? AND tickets.created_at <= ?', start_date.beginning_of_day, end_date.end_of_day)
        .where(taggings: { user_id: user_ids })

      @tickets_by_user = @tickets.joins(:statuses)
        .group('taggings.user_id', 'statuses.name')
        .count

      @sla_status = Ticket.joins(:statuses, :project, :taggings, :sla_tickets)
        .where(sla_tickets: { sla_status: ['Breached'] })
        .where('tickets.created_at >= ? AND tickets.created_at <= ?', start_date.beginning_of_day, end_date.end_of_day)
        .group('taggings.user_id')
        .count

      @sla_target_response_deadline = Ticket.joins(:statuses, :project, :taggings, :sla_tickets)
        .where(sla_tickets: { sla_target_response_deadline: ['Breached'] })
        .where('tickets.created_at >= ? AND tickets.created_at <= ?', start_date.beginning_of_day, end_date.end_of_day)
        .group('taggings.user_id')
        .count

      @sla_resolution_deadline = Ticket.joins(:statuses, :project, :taggings, :sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: ['Breached'] })
        .where('tickets.created_at >= ? AND tickets.created_at <= ?', start_date.beginning_of_day, end_date.end_of_day)
        .group('taggings.user_id')
        .count

      @organized_tickets = @tickets_by_user.each_with_object({}) do |((user_id, status), count), hash|
        hash[user_id] ||= { total: 0 }
        hash[user_id][:total] += count
        hash[user_id][status] = count
      end

      # Always initialize excluded_statuses as an array
      excluded_statuses = %w[Closed Resolved Declined]
      # Allow showing all statuses if requested
      excluded_statuses = [] if params[:all_statuses]
      filtered_chart_data = @organized_tickets.transform_values do |data|
        filtered = data.reject { |k, _| excluded_statuses.include?(k) || k == :total }
        filtered.values.sum
      end
      @tickets_chart_data = filtered_chart_data.transform_keys { |id| User.find(id).name }
      @tickets_per_project = @tickets
        .joins(:statuses)
        .where.not(statuses: { name: excluded_statuses })
        .group('projects.title')
        .count

      # Get all users for mapping assignees (not just team members)
      @all_users = User.all.to_a
      @tickets.pluck(:id)

      # Get assignment events for all users and these tickets, filtered by date range
      assignment_events = Event.where('details ILIKE ?', '%was assigned to the ticket%')
      assignment_events = assignment_events.where('created_at >= ?', start_date.beginning_of_day) if start_date
      assignment_events = assignment_events.where('created_at <= ?', end_date.end_of_day) if end_date

      # For each assignee, count UNIQUE tickets they've been assigned to (case-insensitive)
      @user_total_assigned_tickets = Hash.new { |h, k| h[k] = Set.new }
      @user_name_to_id = {}
      assignment_events.each do |event|
        user = resolve_assigned_user(event, @all_users)
        next unless user
        @user_total_assigned_tickets[user.id] << event.ticket_id
        # Map potential normalized names for later reverse lookup
        @user_name_to_id[user.name.to_s.strip.downcase] = user.id
        @user_name_to_id[[user.first_name, user.last_name].compact.join(' ').strip.downcase] = user.id if user.first_name.present? || user.last_name.present?
      end
      # Count unique ticket IDs per user
      @user_total_assigned_tickets = @user_total_assigned_tickets.transform_values(&:size)

      # Get all breached tickets from ALL tickets ever assigned (not just date-filtered ones)
      all_assigned_ticket_ids = @user_total_assigned_tickets.keys.flat_map do |user_id|
        assignment_events.select { |e| resolve_assigned_user(e, @all_users)&.id == user_id }.map(&:ticket_id)
      end.uniq
      breached_ticket_ids = Ticket.joins(:sla_tickets)
        .where(id: all_assigned_ticket_ids, sla_tickets: { sla_resolution_deadline: ['Breached'] })
        .pluck(:id).to_set

      # For each user, count UNIQUE breached tickets they were assigned to
      @user_breached_tickets = Hash.new { |h, k| h[k] = Set.new }
      assignment_events.where(ticket_id: breached_ticket_ids.to_a).each do |event|
        user = resolve_assigned_user(event, @all_users)
        next unless user
        @user_breached_tickets[user.id] << event.ticket_id
      end
      # Convert sets to counts
      @user_breached_tickets = @user_breached_tickets.transform_values(&:size)

      # Calculate breach percentage for each user
      @user_breach_percentage = {}
      @all_users.each do |user|
        total_assigned = @user_total_assigned_tickets[user.id] || 0
        breached_count = @user_breached_tickets[user.id] || 0
        @user_breach_percentage[user.id] = total_assigned.positive? ? ((breached_count.to_f / total_assigned) * 100).round(2) : 0.0
      end

      respond_to do |format|
        format.html
        team_name = @team.name
        csv_tickets = if params[:all_tickets]
                        @tickets
                      else
                        @tickets.where.not(statuses: { name: %w[Closed Resolved Declined] })
                      end
        format.csv do
          start_str = (params[:start_date].presence && Date.parse(params[:start_date]).strftime('%d-%m-%Y')) || 6.months.ago.to_date.strftime('%d-%m-%Y')
          end_str = (params[:end_date].presence && Date.parse(params[:end_date]).strftime('%d-%m-%Y')) || Date.today.strftime('%d-%m-%Y')
          time_str = Time.now.strftime('%I %M %p')
          filename = "Team Report for #{team_name}_#{start_str}_to_#{end_str}_at_#{time_str}.csv"
          send_data generate_project_report_csv(csv_tickets), filename: filename
        end
      end
    else
      @team = nil
      @team_members = []
      @tickets_by_user = {}
      @user_total_assigned_tickets = {}
      @user_breached_tickets = {}
      @user_breach_percentage = {}
      flash[:alert] = 'Please provide a valid team and date range.'
      render :project_report
    end
  end

  def workload_project_tickets
    authorize! :generate, :report

    # Parse dates (default last 6 months)
    if params[:start_date].present? && params[:end_date].present?
      begin
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
      rescue ArgumentError
        start_date = 6.months.ago.to_date
        end_date = Date.today
      end
    else
      start_date = 6.months.ago.to_date
      end_date = Date.today
    end

    # Find project: allow params[:id] (from routes) or params[:project_id]
    @project = if params[:id].present?
                 Project.find_by(id: params[:id])
               elsif params[:project_id].present?
                 Project.find_by(id: params[:project_id])
               elsif params[:project_title].present?
                 t = params[:project_title].to_s.strip
                 Project.where('LOWER(title) = ?', t.downcase).first || Project.where('title ILIKE ?', "%#{t}%").first
               end

    # If a team is provided, load it and get its member ids
    @team = Team.find_by(id: params[:team_id]) if params[:team_id].present?
    team_user_ids = @team ? @team.users.pluck(:id) : []

    if @project
      # Base scope: tickets for the given project in date range
      @tickets = Ticket.where(project_id: @project.id)
        .where(created_at: start_date.beginning_of_day..end_date.end_of_day)

      # If team filter present, only include tickets that have taggings to those users
      @tickets = @tickets.joins(:taggings).where(taggings: { user_id: team_user_ids }) if team_user_ids.any?

      # By default, show only open tickets unless all_tickets param is provided
      @tickets = @tickets.joins(:statuses).where.not(statuses: { name: %w[Closed Resolved Declined] }) unless params[:all_tickets]

      # Eager load for view performance
      @tickets = @tickets.includes(:project, :statuses, :users).distinct
    else
      @tickets = Ticket.none
      flash.now[:alert] = 'Please select a valid project.' if params[:id].present? || params[:project_id].present? || params[:project_title].present?
    end

    # The tickets partial expects @ticket to be set
    @ticket = @tickets

    respond_to(&:html)
  end

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

    @users = User.where(id: params[:user_id], first_login: true, active: true)
    @selected_user = @users.first

    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : nil
    end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : nil
    from_time = start_date&.beginning_of_day
    to_time = end_date&.end_of_day

    assignment_events_scope = Event.where('events.details ILIKE ?', '%was assigned to the ticket%')

    if @selected_user.present?
      display_name = [@selected_user.first_name, @selected_user.last_name].compact.join(' ').strip
      if display_name.present?
        # Build a safe case-insensitive regex for Postgres (~*).
        # - Escape regex metacharacters in the name
        # - Replace spaces with \s+ so any whitespace (single/multiple/newline) matches
        # - Allow optional whitespace between the name and 'was assigned'
        escaped_for_regex = Regexp.escape(display_name)
        regex_name = escaped_for_regex.gsub(/\s+/, '\\\s+')
        regex = "#{regex_name}\\s*was assigned to the ticket"

        # Also try reversed name (last_name first) in case events store that
        reversed_name = [@selected_user.last_name, @selected_user.first_name].compact.join(' ').strip
        escaped_reversed = Regexp.escape(reversed_name)
        regex_reversed = "#{escaped_reversed.gsub(/\s+/, '\\\s+')}\\s*was assigned to the ticket"

        # Fallback: sanitized ILIKE substring search (also case-insensitive in Postgres)
        ilike_safe = ActiveRecord::Base.sanitize_sql_like(display_name)

        # Use parameterized queries to avoid injection. ~* is case-insensitive regex match in Postgres.
        assignment_events_scope = assignment_events_scope.where(
          'events.details ~* ? OR events.details ~* ? OR events.details ILIKE ?',
          regex, regex_reversed, "%#{ilike_safe}%"
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
    order = %i[years months days hours minutes seconds]

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
        else
          # No filtering applied for unknown status parameter
        end
      end
    else
      @tickets = Ticket.none
      flash[:alert] = 'Please provide a valid user and client.'
      render :show
    end
  end

  private

  def generate_project_report_csv(tickets)
    CSV.generate(headers: true) do |csv|
      csv << ['Project Name', 'Ticket ID', 'Issue Type', 'Assignee', 'Reporter', 'Severity', 'Status', 'Created At',
              'Updated At', 'Last Status Updated', 'Last Comment Updated', 'Summary', 'Content']
      tickets.each do |ticket|
        csv << [
          ticket.project.title,
          ticket.unique_id.gsub('–', '-'),
          ticket.issue,
          ticket.users.map(&:name).select(&:present?).join(', '),
          ticket.user.name,
          ticket.priority,
          ticket.statuses.first&.name || 'N/A',
          ticket.created_at.strftime('%d/%b/%Y %I:%M:%S %p'),
          ticket.updated_at.strftime('%d/%b/%Y %I:%M:%S %p'),
          ticket.add_statuses.order(updated_at: :desc).first&.updated_at&.strftime('%d/%b/%Y %I:%M:%S %p') || 'N/A',
          ticket.issues.order(updated_at: :desc).first&.updated_at&.strftime('%d/%b/%Y %I:%M:%S %p') || 'N/A',
          ticket.subject,
          ticket.content.to_plain_text.truncate(3000)
        ]
      end
    end
  end

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
      times << e.created_at if d.include?('resolved') && (d.include?('status') || d.include?('status changed') || d.include?('changed status') || d.include?('to resolved'))
      times << e.created_at if d.include?('closed') && (d.include?('status') || d.include?('status changed') || d.include?('changed status') || d.include?('to closed'))
      times << e.created_at if d.include?('declined') && (d.include?('status') || d.include?('status changed') || d.include?('changed status') || d.include?('to declined'))
    end

    times.compact.min
  end

  # Resolve the assigned user for an assignment event.
  # 1. Use assigned_user_id if present.
  # 2. Use parsed full name match against user.name.
  # 3. Attempt first + last name combination match.
  # 4. Fallback to first name only if unique.
  def resolve_assigned_user(event, all_users)
    return User.find_by(id: event.assigned_user_id) if event.respond_to?(:assigned_user_id) && event.assigned_user_id.present?
    parsed_name = parse_assignment_details(event.details.to_s)[:assigned_to]
    return nil if parsed_name.blank?
    candidate = all_users.find { |u| u.name.to_s.strip.casecmp?(parsed_name.to_s.strip) }
    return candidate if candidate
    parts = parsed_name.to_s.strip.split(/\s+/)
    if parts.size >= 2
      first = parts.first.downcase
      last = parts.last.downcase
      candidate = all_users.find { |u| u.first_name.to_s.strip.downcase == first && u.last_name.to_s.strip.downcase == last }
      return candidate if candidate
    end
    if parts.size == 1
      first = parts.first.downcase
      candidates = all_users.select { |u| u.first_name.to_s.strip.downcase == first }
      return candidates.first if candidates.size == 1
    end
    nil
  end
end
