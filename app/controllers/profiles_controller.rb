require 'csv'
require 'axlsx'
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

    # Robust date parsing
    from_time, to_time = parse_date_range_for_report(params[:start_date], params[:end_date])

    # Assignment events: using assigned_user_id
    assignment_events_scope = Event.where.not(assigned_user_id: nil)
                                   .where.not(event_type: ['created and assign', 'Updated Issue', 'Priority Updated'])

    assignment_events_scope = assignment_events_scope.where(assigned_user_id: @selected_user.id) if @selected_user.present?

    assignment_events_scope = assignment_events_scope.where(created_at: from_time..to_time) if from_time && to_time

    assignment_ticket_ids = assignment_events_scope.where.not(ticket_id: nil).pluck(:ticket_id)

    # Tickets where user is tagged and reported tickets by user
    tagged_ticket_ids = if @selected_user
                          Ticket.joins(:taggings).where(taggings: { user_id: @selected_user.id }).pluck(:id)
                        else
                          []
                        end
    reported_ticket_ids = @selected_user ? Ticket.where(user_id: @selected_user.id).pluck(:id) : []

    # Union of all ticket ids
    all_ticket_ids = (assignment_ticket_ids + tagged_ticket_ids + reported_ticket_ids).uniq

    # SAFETY CAP: limit to most recent N tickets unless explicitly overridden
    cap = params[:limit].to_i.positive? ? params[:limit].to_i : 300
    if all_ticket_ids.size > cap && !ActiveModel::Type::Boolean.new.cast(params[:all])
      capped_ids = Ticket.where(id: all_ticket_ids)
        .order(created_at: :desc)
        .limit(cap)
        .pluck(:id)
      all_ticket_ids = capped_ids
      flash.now[:notice] = "Showing latest #{cap} tickets for performance. Pass all=true to load everything."
    end

    # Apply date window to tickets if provided
    if from_time && to_time
      scoped_ids = Ticket.where(id: all_ticket_ids)
      scoped_ids = scoped_ids.where('tickets.created_at >= ?', from_time) if from_time
      scoped_ids = scoped_ids.where('tickets.created_at <= ?', to_time) if to_time
      all_ticket_ids = scoped_ids.pluck(:id)
    end

    @tickets = Ticket.where(id: all_ticket_ids)
      .includes({ project: :client }, :events, :issues, :statuses, :sla_tickets)
      .distinct

    # All events for these tickets (not only assignments) within date window if given
    all_events_scope = Event.where(ticket_id: all_ticket_ids).where.not(event_type: ['created and assign', 'Updated Issue', 'Priority Updated'])
    all_events_scope = all_events_scope.where(created_at: from_time..to_time) if from_time && to_time
    @all_ticket_events_by_ticket = all_events_scope
      .select(:ticket_id, :details, :created_at, :id, :assigned_user_id)
      .order(:created_at)
      .group_by(&:ticket_id)

    # First assignment times per ticket for selected user
    @assignment_events = assignment_events_scope.where(ticket_id: all_ticket_ids).includes(:ticket)
    @assigned_at_by_ticket_id = @assignment_events
      .group_by(&:ticket_id)
      .transform_values { |evs| evs.min_by(&:created_at)&.created_at }

    filtered_tickets = @tickets
    @status_counts = filtered_tickets
      .group_by { |ticket| ticket.statuses.first&.name || 'N/A' }
      .transform_values(&:count)

    @tickets_by_client = filtered_tickets
      .group_by { |ticket| ticket.project&.client&.name || 'Unknown Client' }

    @events = @assignment_events.to_a

    @issues = Issue.where(ticket_id: all_ticket_ids)
    @issues = @issues.where(created_at: from_time..to_time) if from_time && to_time
    @issues = @issues.includes(:ticket).to_a

    # Hold time calculations across all tickets regardless of status
    @total_hold_times = {}
    @ticket_hold_time_total_seconds = {}
    if @selected_user
      @tickets.each do |ticket|
        events = (@all_ticket_events_by_ticket[ticket.id] || []).sort_by(&:created_at)
        assignment_like_events = events.select do |e|
          e.details.to_s.include?('was assigned to the ticket') || e.assigned_user_id.present?
        end
        handovers = events.select { |e| e.details.to_s.include?('was handed over') }
        hold_periods = []

        # Filter assignments for selected user
        user_assignments = assignment_like_events.select do |e|
          e.assigned_user_id == @selected_user.id
        end

        user_handovers = handovers.select do |e|
          e.assigned_user_id == @selected_user.id
        end

        user_assignments.each do |assign_event|
          assigned_at = assign_event.created_at
          next_assignment = assignment_like_events.find { |a| a.created_at > assign_event.created_at }
          next_handover = user_handovers.find { |h| h.created_at > assign_event.created_at }
          terminal_time = terminal_state_time_for(ticket)
          candidate_end_times = [next_assignment&.created_at, next_handover&.created_at, terminal_time].compact.select { |t| t > assigned_at }
          end_time = candidate_end_times.min || Time.current
          hold_periods << (end_time - assigned_at)
        end
        @total_hold_times[ticket.id] = hold_periods
        @ticket_hold_time_total_seconds[ticket.id] = hold_periods.sum
      end
    end

    # Average duration assignment->resolved
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

    # Calculate deadline breach status for pie chart
    # Count DISTINCT tickets based on their Target Resolution Deadline from latest event
    @deadline_not_breached_count = 0
    @deadline_breached_count = 0
    @deadline_no_sla_count = 0
    @deadline_debug_info = [] if Rails.env.development?

    # Track processed tickets to ensure uniqueness
    processed_ticket_ids = Set.new

    if @selected_user
      @tickets.each do |ticket|
        # Skip if already processed (ensure distinct count)
        next if processed_ticket_ids.include?(ticket.id)

        # Get all events for this ticket where the selected user was assigned
        ticket_events = @all_ticket_events_by_ticket[ticket.id] || []
        user_assignment_events = ticket_events.select { |e| e.assigned_user_id == @selected_user.id }

        next if user_assignment_events.empty?

        # Mark ticket as processed
        processed_ticket_ids.add(ticket.id)

        # Get the LATEST assignment event for this user on this ticket
        latest_assignment = user_assignment_events.max_by(&:created_at)
        info = parse_assignment_details(latest_assignment.details)

        deadline_status = 'no_sla'
        deadline_str = info[:target_deadline].to_s.strip
        parsed_deadline = nil
        full_details = latest_assignment.details.to_s

        if info[:target_deadline].present? && deadline_str.present?
          # Check if the deadline string is already a status word (common case)
          # IMPORTANT: Check "not breached" BEFORE "breached" to avoid substring matching issues
          deadline_str_lower = deadline_str.downcase
          if deadline_str_lower.include?('not breached') || deadline_str_lower == 'not breached'
            @deadline_not_breached_count += 1
            deadline_status = 'Not Breached'
          elsif deadline_str_lower.include?('no sla') || deadline_str_lower == 'no sla'
            @deadline_no_sla_count += 1
            deadline_status = 'No SLA'
          elsif deadline_str_lower.include?('breached') || deadline_str_lower == 'breached'
            @deadline_breached_count += 1
            deadline_status = 'Breached'
          else
            # Try to parse as datetime
            begin
              # Strategy 1: Direct parsing
              parsed_deadline = DateTime.parse(deadline_str)
            rescue ArgumentError, TypeError
              # Strategy 2: Extract datetime patterns from the string
              # Pattern 1: YYYY-MM-DD HH:MM:SS or YYYY-MM-DD
              if deadline_str =~ /(\d{4}-\d{2}-\d{2}(?:\s+\d{2}:\d{2}(?::\d{2})?)?)/
                begin
                  parsed_deadline = DateTime.parse($1)
                rescue => e2
                  Rails.logger.debug "Pattern 1 parse failed: #{e2.message}" if Rails.env.development?
                end
              # Pattern 2: DD/MM/YYYY or DD-MM-YYYY
              elsif deadline_str =~ /(\d{2}[-\/]\d{2}[-\/]\d{4}(?:\s+\d{2}:\d{2}(?::\d{2})?)?)/
                begin
                  parsed_deadline = DateTime.parse($1)
                rescue => e2
                  Rails.logger.debug "Pattern 2 parse failed: #{e2.message}" if Rails.env.development?
                end
              # Pattern 3: Month DD, YYYY (e.g., "December 31, 2025")
              elsif deadline_str =~ /([A-Za-z]+\s+\d{1,2},?\s+\d{4}(?:\s+\d{2}:\d{2}(?::\d{2})?)?)/
                begin
                  parsed_deadline = DateTime.parse($1)
                rescue => e2
                  Rails.logger.debug "Pattern 3 parse failed: #{e2.message}" if Rails.env.development?
                end
              # Pattern 4: Look for any date-like string in the full details
              elsif full_details =~ /(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})/
                begin
                  parsed_deadline = DateTime.parse($1)
                rescue => e2
                  Rails.logger.debug "Pattern 4 parse failed: #{e2.message}" if Rails.env.development?
                end
              end
            end

            if parsed_deadline
              # Successfully parsed - check if breached
              if Time.current > parsed_deadline
                @deadline_breached_count += 1
                deadline_status = 'Breached'
              else
                @deadline_not_breached_count += 1
                deadline_status = 'Not Breached'
              end
            else
              # Could not parse deadline
              @deadline_no_sla_count += 1
              deadline_status = 'parse_error'
            end
          end
        else
          # No deadline found in event details
          @deadline_no_sla_count += 1
          deadline_status = 'no_deadline'
        end

        # Store debug info in development
        if Rails.env.development?
          @deadline_debug_info << {
            ticket_id: ticket.unique_id,
            ticket_uuid: ticket.id,
            deadline_str: deadline_str.presence || 'N/A',
            full_details_preview: full_details.truncate(100),
            status: deadline_status,
            parsed: parsed_deadline&.strftime('%Y-%m-%d %H:%M:%S'),
            current_time: Time.current.strftime('%Y-%m-%d %H:%M:%S')
          }
        end
      end
    end

    respond_to do |format|
      format.html
      format.csv { send_data generate_user_csv(@users), filename: (@selected_user ? "#{@selected_user.first_name}_#{@selected_user.last_name}_#{Date.today}.csv" : "user_report_#{Date.today}.csv") }
    end
  end

  helper_method :parse_assignment_details, :assigned_at_for, :resolved_at_for, :resolution_duration_for, :format_full_duration, :format_full_duration_human

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

  # Alias for format_full_duration for compatibility
  def format_full_duration_human(total_seconds)
    format_full_duration(total_seconds)
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

  def team_report_breach
    authorize! :generate, :report

    if params[:team_id].present?
      @team = Team.find(params[:team_id])
      @team_members = @team.users
      team_member_ids = @team_members.pluck(:id)

      # Handle custom date range or default to last 6 months
      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
      else
        start_date = 6.months.ago.to_date
        end_date = Date.today
      end

      # Get all tickets that were assigned to team members (past or current) via events.assigned_user_id
      # Filter by ticket creation date
      assigned_ticket_ids = Event.where(assigned_user_id: team_member_ids).where.not(event_type: ['created and assign', 'Updated Issue', 'Priority Updated'])
        .where.not(ticket_id: nil)
        .pluck(:ticket_id)
        .uniq

      @tickets = Ticket.where(id: assigned_ticket_ids)
        .where('tickets.created_at >= ? AND tickets.created_at <= ?', start_date.beginning_of_day, end_date.end_of_day)
        .includes(:statuses, :sla_tickets, :events)

      # Group tickets by status
      @tickets_by_status = @tickets.joins(:statuses)
        .group('statuses.name')
        .count

      # Get total ticket count
      @total_tickets = @tickets.count

      # Get all three types of breached tickets
      sla_status_breached_ids = @tickets.joins(:sla_tickets)
        .where(sla_tickets: { sla_status: 'Breached' })
        .distinct
        .pluck(:id)

      response_deadline_breached_ids = @tickets.joins(:sla_tickets)
        .where(sla_tickets: { sla_target_response_deadline: 'Breached' })
        .distinct
        .pluck(:id)

      resolution_deadline_breached_ids = @tickets.joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
        .distinct
        .pluck(:id)

      no_sla_tickets = @tickets.joins(:sla_tickets)
                               .where(sla_tickets: { sla_resolution_deadline: 'NO SLA' })
                               .distinct
                               .pluck(:id)

      # Any ticket breached in at least one category
      all_breached_ids = (sla_status_breached_ids + response_deadline_breached_ids + resolution_deadline_breached_ids).uniq

      # Calculate overall breach counts
      @sla_status_breached_count = sla_status_breached_ids.count
      @response_deadline_breached_count = response_deadline_breached_ids.count
      @resolution_deadline_breached_count = resolution_deadline_breached_ids.count
      @total_breached_count = all_breached_ids.count
      @no_sla_count = no_sla_tickets.count

      # Calculate breach percentages (100% = perfect, 0% = all breached)
      if @total_tickets.positive?
        @sla_status_breach_percentage = (100 - (@sla_status_breached_count.to_f / @total_tickets * 100)).round(2)
        @response_deadline_breach_percentage = (100 - (@response_deadline_breached_count.to_f / @total_tickets * 100)).round(2)
        @resolution_deadline_breach_percentage = (100 - (@resolution_deadline_breached_count.to_f / @total_tickets * 100)).round(2)
        # Overall performance score is based on Target Resolution Time breaches only
        @overall_breach_percentage = (100 - (@resolution_deadline_breached_count.to_f / @total_tickets * 100)).round(2)
      else
        @sla_status_breach_percentage = 100.0
        @response_deadline_breach_percentage = 100.0
        @resolution_deadline_breach_percentage = 100.0
        @overall_breach_percentage = 100.0
      end

      # Get breached tickets count by status for each breach type
      @sla_status_breached_by_status = Ticket.where(id: sla_status_breached_ids)
        .joins(:statuses)
        .group('statuses.name')
        .count

      @response_deadline_breached_by_status = Ticket.where(id: response_deadline_breached_ids)
        .joins(:statuses)
        .group('statuses.name')
        .count

      @resolution_deadline_breached_by_status = Ticket.where(id: resolution_deadline_breached_ids)
        .joins(:statuses)
        .group('statuses.name')
        .count

      @all_breached_by_status = Ticket.where(id: all_breached_ids)
        .joins(:statuses)
        .group('statuses.name')
        .count

      # Get tickets with NO SLA per status (to exclude from percentage calculation)
      no_sla_ticket_ids = @tickets.joins(:sla_tickets)
        .where(sla_tickets: { sla_resolution_deadline: ['NO SLA', 'N/A', nil] })
        .distinct
        .pluck(:id)

      no_sla_by_status = @tickets.where(id: no_sla_ticket_ids)
        .joins(:statuses)
        .group('statuses.name')
        .count

      # Build table data: status, count, breached counts for each type, breach %
      @status_table_data = []
      @tickets_by_status.each do |status_name, count|
        sla_status_breached = @sla_status_breached_by_status[status_name] || 0
        response_breached = @response_deadline_breached_by_status[status_name] || 0
        resolution_breached = @resolution_deadline_breached_by_status[status_name] || 0
        any_breached = @all_breached_by_status[status_name] || 0
        no_sla_count = no_sla_by_status[status_name] || 0

        # Calculate breach percentage based on resolution deadline, excluding NO SLA tickets
        tickets_with_sla = count - no_sla_count
        status_breach_rate = if tickets_with_sla.positive?
                               (100 - (resolution_breached.to_f / tickets_with_sla * 100)).round(2)
                             else
                               100.0 # No tickets with SLA = perfect score
                             end

        # Check if this status is open or closed
        closed_statuses = ['Closed', 'Resolved', 'Declined']
        total_open = closed_statuses.include?(status_name) ? 0 : count

        @status_table_data << {
          status: status_name,
          total: count,
          total_open: total_open,
          tickets_with_sla: tickets_with_sla,
          no_sla_count: no_sla_count,
          sla_status_breached: sla_status_breached,
          response_deadline_breached: response_breached,
          resolution_deadline_breached: resolution_breached,
          any_breached: any_breached,
          non_breached: count - any_breached,
          breach_percentage: status_breach_rate
        }
      end

      # Sort by specified status order: Assigned, Work in Progress, QA Testing, Client Confirmation Pending, On-Hold, Reopened, Closed, Declined
      status_order = ['Assigned', 'Work in Progress', 'QA Testing', 'Client Confirmation Pending', 'Under Development', 'Awaiting Build', 'On-Hold', 'Reopened', 'Closed', 'Resolved', 'Declined']
      @status_table_data.sort_by! do |row|
        index = status_order.index(row[:status])
        index.nil? ? status_order.length : index # Put unmapped statuses at the end
      end

      # Per-user breach analysis (team members who touched tickets - assigned at least once)
      @user_breach_data = []
      @team_members.each do |user|
        # Tickets that this user touched (via events.assigned_user_id)
        user_ticket_ids = Event.where(assigned_user_id: user.id, ticket_id: assigned_ticket_ids)
                               .where.not(event_type: ['created and assign', 'Updated Issue', 'Priority Updated'])
                               .pluck(:ticket_id)
                               .uniq

        #Create current user tagged tickets add

        current_user_tagged_tickets = Ticket.joins(:statuses, :taggings)
                                            .where(taggings: { user_id: user.id })
                                            .where.not(statuses: { name: ['Closed', 'Resolved', 'Declined'] })
                                            .pluck(:id)
                                            .uniq

        current_user_tagged = current_user_tagged_tickets.count

        user_tickets = @tickets.where(id: user_ticket_ids)
        user_total = user_tickets.count

        # Count only open tickets (excluding Closed, Resolved, Declined)
        closed_statuses = ['Closed', 'Resolved', 'Declined']
        user_total_open = user_tickets.joins(:statuses)
          .where.not(statuses: { name: closed_statuses })
          .distinct
          .count

        next if user_total.zero?

        # Count breaches for each type for this user's tickets
        user_sla_status_breached = user_tickets.joins(:sla_tickets)
          .where(sla_tickets: { sla_status: 'Breached' })
          .distinct
          .count

        user_response_deadline_breached = user_tickets.joins(:sla_tickets)
          .where(sla_tickets: { sla_target_response_deadline: 'Breached' })
          .distinct
          .count

        user_resolution_deadline_breached = user_tickets.joins(:sla_tickets)
          .where(sla_tickets: { sla_resolution_deadline: 'Breached' })
          .distinct
          .count

        # Tickets with any breach
        user_any_breached_ids = user_ticket_ids & all_breached_ids
        user_any_breached = user_any_breached_ids.count

        # Calculate user breach percentage based on Target Resolution Time ONLY (100% = perfect)
        user_breach_rate = user_total.positive? ? (100 - (user_resolution_deadline_breached.to_f / user_total * 100)).round(2) : 100.0

        @user_breach_data << {
          user: user,
          total: user_total,
          total_open: user_total_open,
          sla_status_breached: user_sla_status_breached,
          response_deadline_breached: user_response_deadline_breached,
          resolution_deadline_breached: user_resolution_deadline_breached,
          any_breached: user_any_breached,
          non_breached: user_total - user_any_breached,
          breach_percentage: user_breach_rate,
          current_user_tagged: current_user_tagged
        }
      end

      # Sort by breach percentage (lowest first = most breached)
      @user_breach_data.sort_by! { |row| row[:breach_percentage] }

      respond_to do |format|
        format.html
        format.csv do
          start_str = start_date.strftime('%d-%m-%Y')
          end_str = end_date.strftime('%d-%m-%Y')
          time_str = Time.now.strftime('%I %M %p')
          filename = "Team Breach Report for #{@team.name}_#{start_str}_to_#{end_str}_at_#{time_str}.csv"
          send_data generate_team_breach_csv, filename: filename
        end
      end
    else
      @team = nil
      @team_members = []
      @tickets = Ticket.none
      @status_table_data = []
      @user_breach_data = []
      @total_tickets = 0
      @sla_status_breached_count = 0
      @response_deadline_breached_count = 0
      @resolution_deadline_breached_count = 0
      @total_breached_count = 0
      @sla_status_breach_percentage = 100.0
      @response_deadline_breach_percentage = 100.0
      @resolution_deadline_breach_percentage = 100.0
      @overall_breach_percentage = 100.0
      flash[:alert] = 'Please select a team and date range.'
      respond_to(&:html)
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

  # Parse "Assigned To", "SLA Status", "Target Resolution Deadline" from details text
  # Returns the parsed fields plus the whole details
  def parse_assignment_details(details)
    return { assigned_to: nil, sla_status: nil, target_deadline: nil, details: nil } if details.blank?

    normalized = details.to_s.gsub('was assigned', ' was assigned')

    assigned_to = normalized[/\A\s*(.+?)\s+was assigned to the ticket/i, 1]&.strip

    # Extract SLA Status - handle newlines and multiple whitespace
    # Match "Status:" followed by any whitespace, then capture text until "and" or end
    sla_status = normalized[/Status:\s*\n?\s*(.+?)(?:\s+and\s+|\z)/im, 1]&.strip

    # Extract Target Resolution Deadline (case-insensitive, handles both "deadline" and "Deadline")
    # Pattern: "Target Resolution deadline YYYY-MM-DD HH:MM:SS" or similar
    target_deadline = normalized[/Target Resolution (?:deadline|Deadline)[:\s]*(.+?)(?:\s*and\s+|\z)/i, 1]&.strip

    # If not found, try alternative patterns
    target_deadline ||= normalized[/Resolution (?:deadline|Deadline)[:\s]+(.+?)(?:\s*and\s+|\z)/i, 1]&.strip
    target_deadline ||= normalized[/sla_target_resolution_deadline[:\s]+(.+?)(?:\s*and\s+|\z)/i, 1]&.strip

    {
      assigned_to: assigned_to,
      sla_status: sla_status,
      target_deadline: target_deadline,
      details: details.to_s
    }
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

  # Classify events for enriched display
  def classify_event(details)
    text = details.to_s.downcase
    return 'assignment' if text.include?('was assigned to the ticket')
    return 'handover' if text.include?('was handed over')
    return 'status_change' if text.include?('status') && (text.include?('changed') || text.include?('to '))
    return 'comment' if text.include?('commented') || text.include?('added comment')

    'other'
  end

  # Generate CSV for team breach report
  def generate_team_breach_csv
    CSV.generate(headers: true) do |csv|
      # Header
      csv << ['Team Breach Report']
      csv << ['Team', @team&.name || 'N/A']
      csv << ['Date Range', "#{params[:start_date]} to #{params[:end_date]}"]
      csv << ['Total Tickets', @total_tickets]
      csv << []

      # Overall breach summary
      csv << ['Breach Type', 'Total Breached', 'Performance %', 'Notes']
      csv << ['Initial Response Time (SLA Status)', @sla_status_breached_count, @sla_status_breach_percentage, '']
      csv << ['Target Repair Time (Response Deadline)', @response_deadline_breached_count, @response_deadline_breach_percentage, '']
      csv << ['Target Resolution Time (Resolution Deadline)', @resolution_deadline_breached_count, @resolution_deadline_breach_percentage, '']
      csv << ['Overall Performance Score', @resolution_deadline_breached_count, @overall_breach_percentage, 'Based on Target Resolution Time only']
      csv << []

      # Status breakdown
      csv << ['Breach Analysis by Status']
      csv << ['Status', 'Total Tickets', 'Total (Open)', 'Tickets with SLA', 'NO SLA Count', 'Non-Breached', 'Initial Response Time', 'Target Repair Time', 'Target Resolution Time', 'Any Breach', 'Score %']
      @status_table_data.each do |row|
        csv << [
          row[:status],
          row[:total],
          row[:total_open],
          row[:tickets_with_sla],
          row[:no_sla_count],
          row[:non_breached],
          row[:sla_status_breached],
          row[:response_deadline_breached],
          row[:resolution_deadline_breached],
          row[:any_breached],
          row[:breach_percentage]
        ]
      end
      csv << []

      # User breakdown
      csv << ['Performance by Team Member']
      csv << ['Team Member', 'Total Tickets', 'Total (Open)', 'Tickets with SLA', 'NO SLA Count', 'Non-Breached', 'Target Repair Time', 'Target Resolution Time', 'Any Breach', 'Score %']
      @user_breach_data.each do |row|
        csv << [
          row[:user].name,
          row[:total],
          row[:total_open],
          row[:tickets_with_sla],
          row[:no_sla_count],
          row[:non_breached],
          row[:response_deadline_breached],
          row[:resolution_deadline_breached],
          row[:any_breached],
          row[:breach_percentage]
        ]
      end
      csv << []

      # Legend/Notes
      csv << ['Notes']
      csv << ['- Score % is calculated based on Target Resolution Time breaches only']
      csv << ['- NO SLA tickets are excluded from Score % calculation']
      csv << ['- Total (Open) excludes tickets with status: Closed, Resolved, or Declined']
      csv << ['- Overall Performance Score is based on Target Resolution Time compliance']
      csv << ['- Score ranges: 80-100% (Excellent), 50-79% (Moderate), 0-49% (Critical)']
    end
  end

  # Parse date range from params
  def parse_date_range_for_report(start_date_param, end_date_param)
    start_date = nil
    end_date = nil

    if start_date_param.present?
      begin
        start_date = Date.parse(start_date_param).beginning_of_day
      rescue ArgumentError, TypeError
        start_date = nil
      end
    end

    if end_date_param.present?
      begin
        end_date = Date.parse(end_date_param).end_of_day
      rescue ArgumentError, TypeError
        end_date = nil
      end
    end

    [start_date, end_date]
  end

  # Extract status from event details text
  # Looks for common status patterns in event details
  def extract_status_from_event_details(details)
    return nil if details.blank?

    details_text = details.to_s

    # Check for status patterns
    # Pattern 1: "Status: <status>"
    return $1.strip if details_text =~ /Status:\s*([^,\n]+)/i

    # Pattern 2: "status changed to <status>"
    return $1.strip if details_text =~ /status\s+(?:changed|updated|set)\s+to\s+([^,\n]+)/i

    # Pattern 3: "from <old> to <new>"
    return $1.strip if details_text =~ /from\s+\w+\s+to\s+([^,\n]+)/i

    # Pattern 4: Check for common status keywords
    status_keywords = ['Open', 'In Progress', 'Pending', 'Resolved', 'Closed', 'Declined',
                       'On Hold', 'Waiting', 'Assigned', 'New', 'Reopened']

    status_keywords.each do |keyword|
      return keyword if details_text =~ /\b#{Regexp.escape(keyword)}\b/i
    end

    nil
  end

  # Generate CSV for user report based on report_data
  def generate_report_csv(report_data)
    CSV.generate(headers: true) do |csv|
      csv << ['Event ID', 'Assigned User ID', 'Ticket ID', 'Ticket Unique ID', 'Status', 'Created At', 'Details']

      report_data.each do |row|
        csv << [
          row[:event_id],
          row[:assigned_user_id],
          row[:ticket_id],
          row[:ticket_unique_id],
          row[:status] || 'N/A',
          row[:created_at]&.strftime('%Y-%m-%d %H:%M:%S'),
          row[:details]&.truncate(100)
        ]
      end
    end
  end
end
