require 'csv'
require 'axlsx'

class DataCenterController < ApplicationController
  before_action :authenticate_user!

  def cease_fire_report
    authorize! :generate, :report

    if current_user.has_role?(:ceo)
      @tickets = Ticket.joins(project: :client)
        .where(projects: { id: current_user.projects.ids })
        .joins(:statuses)
        .where.not(statuses: { name: %w[Closed Resolved Declined] })

      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
        @tickets = @tickets.where(created_at: start_date.beginning_of_day..end_date.end_of_day)
        @tickets = @tickets.where(priority: params[:priority]) if params[:priority].present?
      end

      @tickets = @tickets.where(statuses: { name: params[:status] }) if params[:status].present?

      @status_counts = @tickets.group('statuses.name').count
      @xlsx_data = generate_xlsx(@tickets)
      @clients = Client.where(id: @tickets.pluck('clients.id').uniq)

      respond_to do |format|
        format.html # renders view
        filename = "ticket_status_report_ceo_#{Date.today}.xlsx"
        format.xlsx { send_data @xlsx_data, filename: filename }
      end
    elsif params[:client_id].present? || params[:start_date].present? || params[:end_date].present? || params[:status].present?

      @tickets = if current_user.has_role?(:admin) || current_user.has_role?(:observer)
                   Ticket.joins(project: :client)
                 else
                   Ticket.joins(project: :client).where(projects: { id: current_user.projects.ids })
                 end

      @tickets = @tickets.where(projects: { client_id: params[:client_ids] }) if params[:client_ids].present?
      @tickets = @tickets.where(priority: params[:priority]) if params[:priority].present?

      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
        @tickets = @tickets.where(created_at: start_date.beginning_of_day..end_date.end_of_day)
      end

      @tickets = if params[:status].blank?
                   @tickets.joins(:statuses)
                 else
                   @tickets.joins(:statuses).where(statuses: { name: params[:status] })
                 end

      @status_counts = @tickets.joins(:statuses).group('statuses.name').count
      @xlsx_data = generate_xlsx(@tickets)
      @clients = Client.where(id: params[:client_ids])

      respond_to do |format|
        format.html # renders view
        client_name = params[:client_id].present? ? Client.find(params[:client_id]).name : 'all_clients'
        filename = "ticket_status_report_#{client_name}_#{Date.today}.xlsx"
        format.xlsx { send_data @xlsx_data, filename: filename }
      end
    else
      @tickets = Ticket.none
      flash[:alert] = 'Please provide a valid client.'
      render :cease_fire_report
    end
  end

  def email_report
    client = Client.find(params[:client_id])
    tickets = Ticket.joins(project: :client).where(projects: { client_id: client.id })
    xlsx_data = generate_xlsx(tickets)

    # Encode the binary data to Base64
    encoded_xlsx_data = Base64.encode64(xlsx_data)

    # Use the email from the client model
    UserMailer.cease_fire_report_email(client.client_contact_person_email, client.client_contact_person, client.name, encoded_xlsx_data).deliver_later

    # Flash a message indicating the email has been sent
    flash[:notice] = "Report sent to #{client.client_contact_person_email}"

    respond_to do |format|
      format.html # renders view
      client_name = params[:client_id].present? ? Client.find(params[:client_id]).name : 'all_clients'
      filename = "ticket_status_report_#{client_name}_#{Date.today}.xlsx"
      format.xlsx { send_data @xlsx_data, filename: filename }
    end
  end

  def breach_report
    authorize! :generate, :report # Check if the user can generate reports

    if params[:client_id].present?
      @tickets = if current_user.has_role?(:admin) || current_user.has_role?(:observer)
                   Ticket.joins(project: :client)
                 else
                   Ticket.joins(project: :client).where(projects: { id: current_user.projects.ids })
                 end

      @tickets = @tickets.where(projects: { client_id: params[:client_id] }) if params[:client_id].present?
      @tickets = @tickets.joins(:statuses).where(statuses: { name: params[:status] }) if params[:status].present?
      @tickets = @tickets.where(priority: params[:priority]) if params[:priority].present?

      @status_counts = @tickets.joins(:statuses).group('statuses.name').count

      respond_to do |format|
        format.html # Default view
        client_name = Client.find(params[:client_id]).name if params[:client_id].present?
        format.csv { send_data generate_breach_details_csv(@tickets), filename: "breach__report_for_#{client_name}_#{Date.today}.csv" }
      end
    else
      @tickets = Ticket.none
      flash[:alert] = 'Please provide a valid client.'
      render :breach_report
    end
  end

  # User activity report for the admin

  def user_report_view
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
      render :user_report_view
    end
  end

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

      excluded_statuses = %w[Closed Resolved Declined]
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
          time_str = Time.now.strftime('%I-%M_%p')
          filename = "Team Report for #{team_name}_#{start_str}_to_#{end_str}_at_#{time_str}.csv"
          send_data generate_project_report_csv(csv_tickets), filename: filename
        end
      end
    else
      @team = nil
      @team_members = []
      @tickets_by_user = {}
      flash[:alert] = 'Please provide a valid team and date range.'
      render :project_report
    end
  end

  # app/controllers/data_center_controller.rb
  def daily_summary_report
    authorize! :generate, :report

    if params[:team_id].present?
      @team = Team.find(params[:team_id])
      user_ids = @team.users.pluck(:id)
      start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : 6.months.ago.to_date
      end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.today

      tickets_scope = Ticket.joins(:statuses, :taggings)
        .where(taggings: { user_id: user_ids })
        .where('tickets.created_at >= ? AND tickets.created_at <= ?', start_date.beginning_of_day, end_date.end_of_day)

      @daily_summary = tickets_scope.merge(Ticket.daily_summary)
    else
      @team = nil
      @daily_summary = []
      flash[:alert] = 'Please select a team to view daily summary.'
    end
  end

  def assigned_tickets
    @team = Team.find(params[:team_id])

    # Use the same date range logic as project_report
    if params[:start_date].present? && params[:end_date].present?
      start_date = Date.parse(params[:start_date])
      end_date = Date.parse(params[:end_date])
    else
      start_date = 6.months.ago.to_date
      end_date = Date.today
    end

    if params[:user_id]
      @user = User.find(params[:user_id])
      @tickets = Ticket.joins(:statuses, :taggings, :project)
        .where.not(statuses: { name: %w[Resolved Closed Declined] })
        .where(taggings: { user_id: @user.id })
        .where('tickets.created_at >= ? AND tickets.created_at <= ?', start_date.beginning_of_day, end_date.end_of_day)
        .order('projects.title').order('created_at DESC')
    else
      @tickets_by_user = Ticket.joins(:statuses, :taggings, :project)
        .where.not(statuses: { name: %w[Resolved Closed Declined] })
        .where(taggings: { user_id: @team.users.pluck(:id) })
        .where('tickets.created_at >= ? AND tickets.created_at <= ?', start_date.beginning_of_day, end_date.end_of_day)
        .order('projects.title').order('created_at DESC')
        .group_by(&:user)
    end
  end

  def orm_report
    authorize! :generate, :report

    if params[:client_id].present? || params[:days].present?
      @clients = if current_user.has_role?(:admin) || current_user.has_role?(:observer)
                   Client.all
                 else
                   Client.joins(:projects).where(projects: { id: current_user.projects.ids }).distinct
                 end

      days = params[:days].to_i
      outstanding_statuses = %w[Closed Resolved Declined]

      @tickets = if current_user.has_role?(:admin) || current_user.has_role?(:observer)
                   Ticket.joins(project: :client)
                     .joins(:statuses)
                     .where.not(statuses: { name: outstanding_statuses })
                 else
                   Ticket.joins(project: :client)
                     .joins(:statuses)
                     .where(projects: { id: current_user.projects.ids })
                     .where.not(statuses: { name: outstanding_statuses })
                 end

      # Apply filtering if a specific client is selected
      @tickets = @tickets.where(projects: { client_id: params[:client_id] }) if params[:client_id].present?

      # Handle days filter
      if days.positive?
        closed_resolved_tickets = Ticket.joins(project: :client)
          .joins(:statuses)
          .where(statuses: { name: %w[Closed Resolved Declined] })
          .where('tickets.created_at >= ?', days.days.ago)
          .where(projects: { client_id: params[:client_id] })
        @tickets = @tickets.or(closed_resolved_tickets)
      end

      @tickets = @tickets.joins(:statuses).where(statuses: { name: params[:status] }) if params[:status].present?
      @status_counts = @tickets.joins(:statuses).group('statuses.name').count
      @ticket_counts = @tickets.group(:project_id).count
      @project_status_counts = @tickets.joins(:statuses).group(:project_id, 'statuses.name').count

      respond_to do |format|
        format.html
        format.csv do
          client_name = params[:client_id].present? ? Client.find(params[:client_id]).name : 'all_clients'
          filename = "orm_report_#{client_name}_#{Date.today}.csv"
          send_data generate_orm_report_csv(@tickets, @ticket_counts, @project_status_counts), filename: filename
        end
      end
    else
      @tickets = Ticket.none
      flash[:alert] = 'Please provide a valid client and days range.'
      render :orm_report
    end
  end

  def orm_team_report
    authorize! :generate, :report

    return unless params[:team_id].present? || params[:days].present?

    @teams = Team.all if current_user.has_any_role?(:admin, :observer, :project_manager)
    @teams ||= Team.none

    days = params[:days].to_i
    outstanding_statuses = %w[Closed Resolved Declined]

    if params[:team_id].present?
      team = Team.find_by(id: params[:team_id])
      if team.nil?
        @tickets = Ticket.none
        flash[:alert] = 'Please provide a valid team.'
        render :orm_report and return
      end

      # Get user IDs from the team
      user_ids = team.users.pluck(:id)

      # Retrieve tickets associated with the team's users via the taggings table
      @tickets = Ticket.joins(:taggings, :statuses)
        .joins('INNER JOIN add_statuses ON add_statuses.ticket_id = tickets.id') # Join add_statuses
        .where(taggings: { user_id: user_ids })
        .where(
          'statuses.name NOT IN (:outstanding_statuses) OR
                          (statuses.name IN (:outstanding_statuses) AND add_statuses.created_at >= :days_ago)',
          outstanding_statuses: outstanding_statuses,
          days_ago: days.days.ago
        )

      # Ensure non-admin users can only see their own project tickets
      @tickets = @tickets.joins(:project).where(projects: { id: current_user.projects.ids }) unless current_user.has_any_role?(:admin, :observer, :project_manager)

      # Filter by status if provided
      @tickets = @tickets.where(statuses: { name: params[:status] }) if params[:status].present?

      # Aggregate data
      @status_counts = @tickets.joins(:statuses).group('statuses.name').count
      @ticket_counts = @tickets.group(:project_id).count
      @project_status_counts = @tickets.joins(:statuses).group(:project_id, 'statuses.name').count

      respond_to do |format|
        format.html
        if params[:team_id].present?
          team_name = team.name
          filename = "orm_team_report_#{team_name}_#{Date.today}.csv"
          format.csv { send_data generate_orm_team_report_csv(@tickets, @ticket_counts, @project_status_counts), filename: filename }
        end
      end
    else
      @tickets = Ticket.none
      flash[:alert] = 'Please provide a valid team and days range.'
      render :orm_team_report
    end
  end

  def sod_report
    authorize! :generate, :report # Check if the user can generate reports

    # Find the team based on the provided team name
    team = Team.find_by(name: params[:team_name])

    if team
      user_ids = team.users.pluck(:id)
      outstanding_statuses = %w[Closed Resolved Declined]
      report_type = params[:report_type] # 'sod' for start of day, 'eod' for end of day

      base_scope = Ticket.joins(:users, project: :client)
        .joins(:statuses)
        .joins(:add_statuses)
        .where(users: { id: user_ids, active: true })

      # Apply role-based filtering if not admin or observer
      @tickets = if current_user.has_role?(:admin) || current_user.has_role?(:observer)
                   base_scope
                 else
                   base_scope.where(projects: { id: current_user.projects.ids })
                 end

      @tickets = if report_type == 'closed'
                   # Only tickets with outstanding statuses updated in the last 24 hours
                   @tickets.where(statuses: { name: outstanding_statuses })
                     .where('add_statuses.updated_at >= ?', 24.hours.ago)
                 elsif report_type == 'eod'
                   recently_updated_tickets = @tickets
                     .where(statuses: { name: outstanding_statuses })
                     .where('add_statuses.updated_at >= ?', 24.hours.ago)
                   @tickets.where.not(statuses: { name: outstanding_statuses }).or(recently_updated_tickets)
                 else
                   @tickets.where.not(statuses: { name: outstanding_statuses })
                 end.order('add_statuses.updated_at DESC')
    else
      @tickets = [] # Initialize @tickets as an empty array if the team is not found
      flash[:alert] = 'Team not found.'
    end

    respond_to do |format|
      format.html # Default view
      format.csv do
        team_name = team&.name || 'unknown_team'
        filename = "#{report_type == 'sod' ? 'start_of_day' : 'end_of_day'}_report_#{team_name}_#{Date.today}.csv"
        send_data generate_start_of_day_csv(@tickets), filename: filename
      end
    end
  end

  # Team send emails for the day

  def daily_report
    team = Team.find_by(name: params[:team_name])

    if team
      outstanding_statuses = %w[Closed Resolved Declined]
      report_type = params[:report_type] || 'sod'

      user_ids = team.users.pluck(:id)

      base_scope = Ticket.joins(:users, project: :client)
        .joins(:statuses, :add_statuses, :taggings)
        .where(users: { id: user_ids, active: true })

      tickets = if current_user.has_role?(:admin) || current_user.has_role?(:observer)
                  base_scope
                else
                  base_scope.where(projects: { id: current_user.projects.ids })
                end

      tickets = if report_type == 'closed'
                  tickets.where(statuses: { name: outstanding_statuses })
                    .where('add_statuses.updated_at >= ?', 24.hours.ago)
                elsif report_type == 'eod'
                  recently_updated = tickets.where(statuses: { name: outstanding_statuses })
                    .where('add_statuses.updated_at >= ?', 24.hours.ago)
                  tickets.where.not(statuses: { name: outstanding_statuses }).or(recently_updated)
                else
                  tickets.where.not(statuses: { name: outstanding_statuses })
                end.order('add_statuses.updated_at DESC')

      hod_emails = team.users.select { |u| u.has_role?(:hod) }.map(&:email)
      mail_options = {}
      mail_options[:cc] = hod_emails if hod_emails.any?

      team.users.each do |user|
        tagged_tickets = tickets.select('tickets.*, add_statuses.updated_at')
          .joins(:taggings)
          .where(taggings: { user_id: user.id })
          .order('add_statuses.updated_at DESC')
          .distinct

        if tagged_tickets.any?
          UserMailer.daily_ticket_email(user, tagged_tickets.to_a, mail_options).deliver_later
        elsif report_type == 'closed'
          # Send an empty notice for the user with no closed/resolved/declined tickets
          UserMailer.daily_ticket_email(user, [], mail_options).deliver_later
        end
      end

      redirect_back fallback_location: root_path, notice: 'SOD report emailed successfully.'
    else
      redirect_back fallback_location: root_path, alert: 'Team not found.'
    end
  end

  def send_team_ticket_emails
    team = Team.find_by(name: params[:team_name])
    return redirect_back fallback_location: root_path, alert: 'Team not found.' unless team

    outstanding_statuses = %w[Closed Resolved Declined]
    user_ids = team.users.pluck(:id)

    base_scope = Ticket.joins(:users, project: :client)
      .joins(:statuses, :taggings)
      .where(users: { id: user_ids, active: true })
      .where.not(statuses: { name: outstanding_statuses })

    team.users.each do |user|
      user_tickets = base_scope.where(taggings: { user_id: user.id }).distinct
      UserMailer.morning_ticket_email(user, user_tickets.to_a).deliver_later if user_tickets.any?
    end

    redirect_back fallback_location: root_path, notice: 'Ticket emails sent to team members.'
  end

  # CBK Report for Groupware/Elma

  def cbk_groupware_report
    # groupware Report

    if params[:groupware_id].present?
      @groupware = Groupware.find(params[:groupware_id])
      @tickets = Ticket.joins(software: :groupwares)
        .where(groupwares: { id: @groupware.id })
        .joins(:sla_tickets)

      if params[:start_date].present? && params[:end_date].present?
        start_date = Date.parse(params[:start_date])
        end_date = Date.parse(params[:end_date])
        @tickets = @tickets.where('tickets.created_at >= ? AND tickets.created_at <= ?', start_date.beginning_of_day, end_date.end_of_day)
      end

      @tickets = @tickets.joins(project: :client).where(clients: { country_code: params[:country_code] }) if params[:country_code].present?
    else
      @tickets = Ticket.none
    end
    start_date = Date.parse(params[:start_date]) if params[:start_date].present?
    month_name = start_date ? Date::MONTHNAMES[start_date.month] : Date::MONTHNAMES[Date.today.month]

    respond_to do |format|
      format.html { render :cbk_groupware_report }
      format.csv { send_data generate_cbk_groupware_report_csv(@tickets), filename: "cbk_report_for #{month_name} and #{Date.today}.csv" }
    end
  end

  def user_report
    authorize! :generate, :report

    # Always initialize instance variables
    @users = []
    @tickets = Ticket.none
    @events = []
    @issues = []
    @status_counts = {}
    @tickets_by_client = {}
    @assigned_at_by_ticket_id = {}
    @all_ticket_events_by_ticket = {}

    # If no filters, render the form normally
    return respond_to(&:html) unless params[:user_id].present? || params[:start_date].present? || params[:end_date].present?

    @users = User.where(id: params[:user_id])
    @selected_user = @users.first

    start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : nil
    end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : nil
    from_time = start_date&.beginning_of_day
    to_time = end_date&.end_of_day

    # Identify assignment events via details text (no events.name column available)
    assignment_events_scope = Event.where('events.details ILIKE ?', '%was assigned to the ticket%')

    if @selected_user.present?
      display_name = [@selected_user.first_name, @selected_user.last_name].compact.join(' ').strip
      if display_name.present?
        escaped = ActiveRecord::Base.sanitize_sql_like(display_name)
        # Support the known formatting issue: missing space before "was"
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

    # Ticket IDs assigned to the selected user within the range
    ticket_ids = assignment_events_scope.where.not(ticket_id: nil).distinct.pluck(:ticket_id)

    # Preload for display
    @assignment_events = assignment_events_scope.includes(:ticket)

    # Map the earliest assignment time per ticket for the selected user
    @assigned_at_by_ticket_id = @assignment_events
      .group_by(&:ticket_id)
      .transform_values { |evs| evs.min_by(&:created_at)&.created_at }

    # Preload all events for those tickets (used for resolved detection)
    @all_ticket_events_by_ticket = Event
      .where(ticket_id: ticket_ids)
      .select(:ticket_id, :details, :created_at)
      .group_by(&:ticket_id)

    @tickets = Ticket.where(id: ticket_ids)
      .includes({ project: :client }, :events, :issues, :statuses, :sla_tickets)
      .distinct

    # Status counts with your original logic
    filtered_tickets = @tickets
    @status_counts = filtered_tickets
      .group_by { |ticket| ticket.statuses.first&.name || 'N/A' }
      .transform_values(&:count)

    @tickets_by_client = filtered_tickets
      .group_by { |ticket| ticket.project&.client&.name || 'Unknown Client' }

    # Only assignment events for the events table
    @events = @assignment_events.to_a

    # Issues related to the matched tickets (optionally filter by date range)
    @issues = Issue.where(ticket_id: ticket_ids)
    @issues = @issues.where(created_at: from_time..to_time) if from_time || to_time
    @issues = @issues.includes(:ticket).to_a

    # Average time from assignment to resolution across resolved tickets
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

    respond_to do |format|
      format.html
      format.csv { send_data generate_user_csv(@users), filename: "user_report_#{Date.today}.csv" }
    end
  end

  helper_method :parse_assignment_details, :assigned_at_for, :resolved_at_for, :resolution_duration_for

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

  def generate_orm_report_csv(tickets, ticket_counts, project_status_counts)
    CSV.generate(headers: true) do |csv|
      csv << ['Project Name', 'Total Number of Tickets', 'Status', 'Count']
      ticket_counts.each do |project_id, total_count|
        project = Project.find(project_id)
        csv << [project.title, total_count, '', '']
        project_status_counts.select { |k, _| k.first == project_id }.each do |(_proj_id, status), count|
          csv << ['', '', status, count]
        end
      end

      csv << []
      csv << ['Client Name', 'Ticket ID', 'Issue Type', 'Assignee', 'Reporter', 'Severity', 'Status', 'Created At', 'Updated At',
              'Status Updated At', 'Last Comment Updated At', 'Summary', 'Resolution', 'Due Date']
      tickets.each do |ticket|
        csv << [
          ticket.project.client.name.gsub('–', '-') || '',
          ticket.unique_id.gsub('–', '-') || '',
          ticket.issue,
          ticket.users.map(&:name).select(&:present?).join(', ') || '',
          ticket.user.name || '',
          ticket.priority || '',
          ticket.statuses.first&.name || 'N/A',
          ticket.created_at.strftime('%d/%b/%Y %I:%M:%S %p'),
          ticket.updated_at.strftime('%d/%b/%Y %I:%M:%S %p'),
          ticket.add_statuses.order(updated_at: :desc).first&.updated_at&.strftime('%d/%b/%Y %I:%M:%S %p') || 'N/A',
          ticket.issues.order(updated_at: :desc).first&.updated_at&.strftime('%d/%b/%Y %I:%M:%S %p') || 'N/A',
          ticket.subject,
          ticket.content.to_plain_text.truncate(3000),
          ticket.due_date&.strftime('%d/%b/%Y') || 'N/A'

        ]
      end
    end
  end

  def generate_orm_team_report_csv(tickets, ticket_counts, project_status_counts)
    all_statuses = project_status_counts.keys.map { |(_project_id, status)| status }.uniq
    CSV.generate(headers: true) do |csv|
      csv << (['Project Name', 'Total Number of Tickets'] + all_statuses)
      ticket_counts.each do |project_id, total_count|
        project = Project.find(project_id)

        # Build a hash for statuses of the current project
        status_counts = all_statuses.map do |status|
          project_status_counts.fetch([project_id, status], 0)
        end

        csv << ([project.title, total_count] + status_counts)
      end

      csv << []
      csv << ['Client Name', 'Ticket ID', 'Issue Type', 'Assignee', 'Reporter', 'Severity', 'Status', 'Created At',
              'Status Updated At', 'Summary', 'Last Comment Updated At', 'Due Date']
      tickets.each do |ticket|
        csv << [
          ticket.project.client.name.gsub('–', '-'),
          ticket.unique_id.gsub('–', '-'),
          ticket.issue,
          ticket.users.map(&:name).select(&:present?).join(', '),
          ticket.user.name,
          ticket.priority,
          ticket.statuses.first&.name || 'N/A',
          ticket.created_at.strftime('%d/%b/%Y %I:%M:%S %p'),
          ticket.add_statuses.order(updated_at: :desc).first&.updated_at&.strftime('%d/%b/%Y %I:%M:%S %p') || 'N/A',
          ticket.subject,
          ticket.issues.order(updated_at: :desc).first&.updated_at&.strftime('%d/%b/%Y %I:%M:%S %p') || 'N/A',
          ticket.due_date&.strftime('%d-%b-%Y') || 'N/A'
        ]
      end
    end
  end

  def generate_project_report_csv(tickets)
    CSV.generate(headers: true) do |csv|
      csv << ['Project Name', 'Ticket ID', 'Issue Type', 'Assignee', 'Reporter', 'Severity', 'Status', 'Created At',
              'Updated At', 'Summary', 'Content']
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
          ticket.subject,
          ticket.content.to_plain_text.truncate(3000)
        ]
      end
    end
  end

  def generate_xlsx(tickets)
    package = Axlsx::Package.new
    workbook = package.workbook

    # Define styles for each status
    styles = {
      'New' => workbook.styles.add_style(bg_color: 'EF4444', sz: 9, border: { style: :thin, color: '000000' }), # Red
      'Closed' => workbook.styles.add_style(bg_color: 'D9EAD3', sz: 9, border: { style: :thin, color: '000000' }), # Green
      'Resolved' => workbook.styles.add_style(bg_color: 'D9EAD3', sz: 9, border: { style: :thin, color: '000000' }), # Green
      'Reopened' => workbook.styles.add_style(bg_color: '87F1D1D', sz: 9, border: { style: :thin, color: '000000' }), # Dark Red
      'Under Development' => workbook.styles.add_style(bg_color: '93C5FD', sz: 9, border: { style: :thin, color: '000000' }), # Light Blue
      'Work in Progress' => workbook.styles.add_style(bg_color: 'cccccc', sz: 9, border: { style: :thin, color: '000000' }), # Gray
      'QA Testing' => workbook.styles.add_style(bg_color: 'EC4899', sz: 9, border: { style: :thin, color: '000000' }), # Pink
      'Awaiting Build' => workbook.styles.add_style(bg_color: '1F2937', sz: 9, border: { style: :thin, color: '000000' }), # Dark Slate Gray
      'Client Confirmation Pending' => workbook.styles.add_style(bg_color: 'FFF2CC', sz: 9, border: { style: :thin, color: '000000' }), # Purple
      'On-Hold' => workbook.styles.add_style(bg_color: 'FF0000', sz: 9, border: { style: :thin, color: '000000' }), # Yellow
      'Assigned' => workbook.styles.add_style(bg_color: '1E40AF', fg_color: 'FFFFFF', sz: 9, border: { style: :thin, color: '000000' }), # Navy
      'Declined' => workbook.styles.add_style(bg_color: '000000', fg_color: 'FFFFFF', sz: 9, border: { style: :thin, color: '000000' }) # Dark Slate Gray
    }

    # Define header style with borders
    header_style = workbook.styles.add_style(b: true, sz: 9, border: { style: :thin, color: '000000' })

    # Default row style with borders
    default_row_style = workbook.styles.add_style(sz: 9, border: { style: :thin, color: '000000' })

    # Group tickets by project
    tickets.group_by { |ticket| ticket.project.title }.each do |project_title, project_tickets|
      truncated_title = project_title[0, 31] # Truncate to 31 characters
      workbook.add_worksheet(name: truncated_title) do |sheet|
        # Add header row with the header style
        sheet.add_row(
          ['Ticket ID', 'Project Name', 'Severity', 'Summary', 'Issue Type', 'Status', 'Assignee To',
           'Reporter', 'Details', 'Created', 'Status Updated At', 'Last Comment Updated At', 'Due Date',
           "Comments #{Date.today.strftime('%d/%b/%Y')}"],
          style: header_style
        )
        project_tickets.sort_by { |ticket| -ticket.created_at.to_i }.each do |ticket|
          status = ticket.statuses.first&.name || 'N/A'
          row_style = styles[status] || default_row_style

          sheet.add_row [
            ticket.unique_id.gsub('–', '-'),
            ticket.project.title,
            ticket.priority,
            ticket.subject,
            ticket.issue,
            status,
            ticket.users.map(&:name).select(&:present?).join(', '),
            ticket.user.name,
            ticket.content.to_plain_text.truncate(3000),
            ticket.created_at.strftime('%d/%b/%Y %I:%M:%S %p'),
            ticket.add_statuses.order(updated_at: :desc).first&.updated_at&.strftime('%d/%b/%Y %I:%M:%S %p') || 'N/A',
            ticket.issues.order(updated_at: :desc).first&.updated_at&.strftime('%d/%b/%Y %I:%M:%S %p') || 'N/A',
            ticket.due_date&.strftime('%d/%b/%Y') || 'N/A'
          ], style: row_style
        end
      end
    end

    package.to_stream.read
  end

  def generate_breach_details_csv(tickets)
    CSV.generate(headers: true) do |csv|
      csv << ['Created At', 'Ticket ID', 'Support Desk', 'Severity', 'Summary', 'Issue Type', 'Status', 'Assignee To', 'Reporter',
              'SLA Status', 'Target Response Deadline', 'Resolution Deadline']
      tickets.each do |ticket|
        sla_ticket = SlaTicket.find_by(ticket_id: ticket.id)
        csv << [
          ticket.created_at.strftime('%d/%b/%Y %I:%M:%S %p'),
          ticket.unique_id.gsub('–', '-'),
          ticket.project.title,
          ticket.priority,
          ticket.subject,
          ticket.issue,
          ticket.statuses.first&.name || 'N/A',
          ticket.users.map(&:name).select(&:present?).join(', '),
          ticket.user.name,
          sla_ticket&.sla_status || 'N/A',
          sla_ticket&.sla_target_response_deadline.presence || 'not breached',
          sla_ticket&.sla_resolution_deadline.presence || 'not breached'
        ]
      end
    end
  end

  # Generate user report in CSV format
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

  def generate_start_of_day_csv(tickets)
    bom = "\uFEFF" # Add BOM to ensure UTF-8 compatibility in Excel

    tickets = tickets.includes(
      :user,
      :users,
      :statuses,
      :add_statuses,
      issues: :rich_text_content
    )

    csv_data = CSV.generate(headers: true) do |csv|
      csv << ['Service Desk', 'Issue Key', 'Summary', 'Issue Type', 'Assignee', 'Reporter', 'Priority', 'Status', 'Created At',
              'Status Updated At', 'Comment Added At', 'Content', 'Due Date']

      tickets.each do |ticket|
        latest_issue = ticket.issues.max_by(&:updated_at) # Using in-memory sorting after eager loading

        csv << [
          ticket.project.title,
          ticket.unique_id.gsub('–', '-'),
          ticket.subject,
          ticket.issue,
          ticket.users.map(&:name).select(&:present?).join(', '),
          ticket.user&.name || 'N/A',
          ticket.priority,
          ticket.statuses.first&.name || 'N/A',
          ticket.created_at.strftime('%d/%b/%Y %I:%M:%S %p'),
          ticket.add_statuses.order(updated_at: :desc).first&.updated_at&.strftime('%d/%b/%Y %I:%M:%S %p') || 'N/A',
          latest_issue&.created_at&.strftime('%d/%b/%Y %I:%M:%S %p') || 'N/A',
          latest_issue # rubocop:disable Style/SafeNavigationChainLength
            &.content&.to_plain_text&.truncate(800)&.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')&.gsub("\u00A0", ' ')&.gsub(/[^\p{Print}]/, '') || 'N/A',
          ticket.due_date&.strftime('%d/%b/%Y %I:%M:%S %p') || 'N/A'
        ]
      end
    end

    bom + csv_data
  end

  def generate_cbk_groupware_report_csv(tickets)
    CSV.generate(headers: true) do |csv|
      csv << ['Ticket ID', 'Project Name', 'Severity', 'Summary', 'Issue Type', 'Status',
              'Assignee', 'Reporter by', 'Created At', 'Closed']

      tickets.each do |ticket|
        csv << [
          ticket.unique_id,
          ticket.project.title,
          ticket.priority,
          ticket.subject,
          ticket.issue,
          ticket.statuses.first&.name || 'N/A',
          ticket.users.map(&:name).select(&:present?).join(', '),
          ticket.user.name,
          ticket.created_at.strftime('%m/%d/%Y %H:%M'),
          (ticket.add_statuses.order(updated_at: :desc).first&.updated_at&.strftime('%m/%d/%Y %H:%M') || 'N/A' if %w[Closed Resolved].include?(ticket.statuses.first&.name))
        ]
      end
    end
  end
end
