class ProjectController < ApplicationController
  before_action :set_project, only: %i[show edit update destroy assign_user manage_users unassign_user]
  before_action :authenticate_user!
  load_and_authorize_resource
  # GET /projects
  def index
    if params[:query].present?
      query_str = params[:query].strip

      # Replace only the first hyphen with an en dash if there are exactly two hyphens
      formatted_query = query_str.count('-') == 2 ? query_str.sub('-', '–') : query_str

      @project = Project.joins(:tickets)
        .where('projects.title ILIKE :query
              OR projects.description ILIKE :query
              OR tickets.unique_id ILIKE :query
              OR tickets.subject ILIKE :query',
               query: "%#{formatted_query}%")
        .distinct
    else
      @project = Project.all.with_rich_text_content.order('projects.title ASC')
    end

    @project = @project.joins(:users).where(users: { id: current_user.id }) unless current_user.has_any_role?(:admin, :observer)

    @tickets = if params[:query].present?
                 if current_user.has_any_role?(:admin, :observer) || @project.any? { |project| project.users.include?(current_user) }
                   Ticket.joins(:project)
                     .where('unique_id ILIKE :query OR subject ILIKE :query', query: "%#{formatted_query}%")
                     .where(projects: { id: @project.ids })
                 else
                   Ticket.none
                 end
               else
                 Ticket.none
               end

    @per_page = 10
    @page = (params[:page] || 1).to_i
    @total_pages = (@project.count / @per_page.to_f).ceil
    @project = @project.offset((@page - 1) * @per_page).limit(@per_page)
  end

  # GET /projects/id
  def show
    if current_user.has_role?(:admin) || @project.users.include?(current_user) || current_user.has_role?(:observer) || current_user.has_role?(:agent)
      @per_page = 10
      @page = params[:page].to_i.positive? ? params[:page].to_i : 1
      offset = (@page - 1) * @per_page

      @ticket = @project.tickets
        .left_joins(:rich_text_content, :statuses, :users, :add_statuses)
        .includes(:users, :statuses, :add_statuses)

      @statuses = @project.tickets.joins(:statuses).distinct.pluck('statuses.name')

      # Filters
      if params[:start_date].present? && params[:end_date].present?
        @ticket = @ticket.where('tickets.created_at::date BETWEEN ? AND ?', params[:start_date], params[:end_date])
      elsif params[:start_date].present?
        @ticket = @ticket.where('tickets.created_at::date >= ?', params[:start_date])
      elsif params[:end_date].present?
        @ticket = @ticket.where('tickets.created_at::date <= ?', params[:end_date])
      end

      if params[:status].present?
        statuses = Array(params[:status])
        @ticket = @ticket.where(statuses: { name: statuses })
      end
      @ticket = @ticket.where('priority ILIKE ?', params[:priority]) if params[:priority].present?
      @ticket = @ticket.where('issue ILIKE ?', params[:issue]) if params[:issue].present?
      @ticket = @ticket.where(users: { id: params[:user_id] }) if params[:user_id].present?

      # Full-text-like search
      if params[:query].present?
        query = "%#{params[:query]}%"
        @ticket = @ticket.where(
          'action_text_rich_texts.body ILIKE :q OR issue ILIKE :q OR priority ILIKE :q OR statuses.name ILIKE :q OR unique_id ILIKE :q
        OR users.first_name ILIKE :q OR users.last_name ILIKE :q OR tickets.created_at::text ILIKE :q',
          q: query
        )
      end

      # All assigned tickets and open tickets and closed tickets
      @ticket = @ticket.joins(:users).where(users: { id: current_user.id }) if params[:filter] == 'Assigned'
      # All assigned and opened tickets
      @ticket = @ticket.joins(:users).where(users: { id: current_user.id }).where.not(statuses: { name: %w[Closed Resolved Declined] }) if params[:filter] == 'Assigned_opened'

      # All assigned and closed tickets
      @ticket = @ticket.joins(:users).where(users: { id: current_user.id }).where(statuses: { name: %w[Closed Resolved Declined] }) if params[:filter] == 'Assigned_closed'

      # All open tickets for all users
      @ticket = @ticket.joins(:users).where.not(statuses: { name: %w[Closed Resolved Declined] }) if params[:filter] == 'Open'
      # All open tickets for all users
      @ticket = @ticket.joins(:users, :statuses).where(statuses: { name: %w[Closed Resolved Declined] }) if params[:filter] == 'Closed_for_all'

      # All closed tickets for tickets closed by the current user

      # Ordering
      @selected_order = params[:order]
      @ticket = @ticket.order(created_at: params[:order] == 'asc' ? :asc : :desc)

      # Paginate main result
      @ticket_count = @ticket.count
      @total_pages = (@ticket_count / @per_page.to_f).ceil
      @ticket = @ticket.offset(offset).limit(@per_page)

      # Last month tickets - paginated if filter active
      @use_last_month_filter = params[:last_month].present?
      if @use_last_month_filter
        @last_one_month_tickets = @project.tickets
          .where('created_at >= ?', 1.month.ago)
          .order(created_at: :desc)
          .offset(offset)
          .limit(@per_page)
      end

      # Search by issue/subject - also paginate
      @search_ticket_issue_and_subject = if params[:search].present?
                                           @project.tickets
                                             .where('issue ILIKE :q OR subject ILIKE :q', q: "%#{params[:search]}%")
                                             .offset(offset)
                                             .limit(@per_page)
                                         else
                                           @project.tickets.none
                                         end

      # Misc
      @selected_status = params[:status]
      @selected_priority = params[:priority]
      @selected_issue = params[:issue]
      @selected_user_id = params[:user_id]
      @selected_start_date = params[:start_date]
      @selected_end_date = params[:end_date]

      @created_tickets = @project.tickets.where(user_id: current_user.id).count
      @assigned_tickets_count = @project.tickets.joins(:users).where(users: { id: current_user.id }).count
      @assigned_and_tickets = @project.tickets.joins(:users, :statuses).where(users: { id: current_user.id }).where.not(statuses: { name: %w[Closed Resolved Declined] }).count
      @closed_assigned_tickets = @project.tickets.joins(:users, :statuses)
        .where(users: { id: current_user.id })
        .where(statuses: { name: %w[Closed Resolved] }).count
      @closed_tickets = @project.tickets.joins(:statuses).where(statuses: { name: %w[Closed Resolved] }).count
      @breached_target_tickets_count = @project.tickets.count_target_breached_sla
      @total_tickets_open = @project.tickets.joins(:statuses).where.not(statuses: { name: %w[Closed Resolved Declined] }).count
    else
      redirect_to root_path, alert: 'You are not authorized to view this content.'
    end
  end

  # GET /projects/new
  def new
    @project = Project.new
  end

  # GET /projects/id/edit
  def edit; end

  # POST /projects
  def create
    @project = Project.new(project_params)
    audit_on_create(@project)
    respond_to do |format|
      # Check if the user has the appropriate role
      if current_user.has_role?(:admin) || current_user.has_role?('project_manager')
        # Validate the presence of content
        if @project.content.blank?
          @project.errors.add(:content, 'Subject cannot be blank.') # Add validation error
          # Render the form with validation errors
          format.html { render :new, status: :unprocessable_entity }
        elsif @project.save(validate: false)
          @project.users << @project.user if @project.users.empty?
          current_user.add_role :creator, @project

          # Persisted email: notify the initially assigned user on project creation
          assigned = @project.user
          if assigned.present? && !assigned.has_role?(:ceo)
            Messaging::EmailSender
              .send_email(
                'Support Desk Assignment',
                to: [assigned.email],
                actor: current_user,
                priority: :normal,
                type: 'project_create_assign'
              )
              .use_template(view: 'user_mailer/assignment_email', assigns: { user: assigned, project: @project, current_user:, assigned_user: assigned })
              .set_source('project', @project.id)
              .set_party('user', assigned.id)
              .send(queue: true)
          end
          format.html { redirect_to project_path(@project), notice: 'Support Desk was successfully created.' }
        else
          format.html { render :new, status: :unprocessable_entity }
        end
      else
        # Render an unauthorized error
        format.html do
          render :new, status: :unprocessable_entity, notice: 'You are not authorized to create a Support Desk.'
        end
      end
    end
  end

  # PATCH/PUT /projects/id
  # PATCH/PUT /projects/id
  def update
    audit_on_update(@project)
    respond_to do |format|
      @project.assign_attributes(project_params)
      if @project.save(validate: false)
        current_user.add_role :editor, @project
        format.html { redirect_to project_path(@project), notice: 'Support Desk was successfully updated.' }
      else
        format.html { render 'edit', status: :unprocessable_entity }
      end
    rescue ActiveRecord::RecordNotUnique
      format.html { redirect_to edit_project_path(@project), alert: 'Duplicate groupware assignment detected. Please check your input.' }
    end
  end

  # DELETE /projects/id
  def destroy
    if audit_soft_delete(@project)
      # soft-deleted
    else
      @project.destroy
    end
    respond_to do |format|
      format.html { redirect_to project_url, notice: 'Support Desk was successfully deleted.' }
    end
  end

  def manage_users
    # Get the clients of CRaft silicon
    @non_craft_silicon_users = @project.users.reject { |user| user.email.end_with?('@craftsilicon.com') }

    # Get the staff who have the email of Craft silicon
    @craft_silicon_users = @project.users.select { |user| user.email.end_with?('@craftsilicon.com') }
    render layout: false
  end

  def assign_user
    if @project.users.include?(User.find(params[:user_id]))
      redirect_to @project, notice: "#{user.name}  has already been assigned."
    else
      @project = Project.find(params[:id])
      user = User.find(params[:user_id])
      @project.user = current_user
      @project.users << user

      # Log explicit assignment activity
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@project)
        .event('project.assign_user')
        .with_properties(assigned_user_id: user.id, assigned_user_email: user.email)
        .log("Assigned #{user.name} to Project ##{@project.id}")

      # Send email to the newly assigned user
      # if current user has role :ceo do not send email to the user

      unless user.has_role?(:ceo)
        Messaging::EmailSender
          .send_email(
            'Support Desk Assignment',
            to: [user.email],
            actor: current_user,
            priority: :normal,
            type: 'project_assign'
          )
          .use_template(view: 'user_mailer/assignment_email', assigns: { user:, project: @project, current_user:, assigned_user: user })
          .set_source('project', @project.id)
          .set_party('user', user.id)
          .send(queue: true)
      end
      # @project.users.each do |project_user|
      #  next if project_user == current_user

      #  UserMailer.assignment_email(project_user, @project, current_user, assigned_user).deliver_later
      #  end

      redirect_to @project, notice: "#{user.name} was successfully assigned."
    end
  end

  def add_team
    @project = Project.find(params[:id])
    team = Team.find(params[:team_id])
    @project.user = current_user

    team.users.each do |user|
      next if @project.users.include?(user)

      @project.users << user
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@project)
        .event('project.add_team_user')
        .with_properties(team_id: team.id, user_id: user.id)
        .log("Added #{user.name} to Project ##{@project.id} via Team ##{team.id}")
      Messaging::EmailSender
        .send_email(
          'Support Desk Assignment',
          to: [user.email],
          actor: current_user,
          priority: :normal,
          type: 'project_assign_team'
        )
        .use_template(view: 'user_mailer/assignment_email', assigns: { user:, project: @project, current_user:, assigned_user: user })
        .set_source('project', @project.id)
        .set_party('user', user.id)
        .send(queue: true)
    end

    redirect_to @project, notice: 'Team and its users were successfully added to the project.'
  end

  def remove_team
    @project = Project.find(params[:id])
    team = Team.find(params[:team_id])

    team.users.each do |user|
      @project.users.delete(user)
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@project)
        .event('project.remove_team_user')
        .with_properties(team_id: team.id, user_id: user.id)
        .log("Removed #{user.name} from Project ##{@project.id} via Team ##{team.id}")
    end

    redirect_to @project, notice: 'Team and its users were successfully removed from the project.'
  end

  def unassign_user
    @project = Project.find(params[:id])
    user = User.find(params[:user_id])
    @project.users.delete(user)
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@project)
      .event('project.unassign_user')
      .with_properties(user_id: user.id)
      .log("Unassigned #{user.name} from Project ##{@project.id}")
    redirect_to @project, notice: "#{user.name}  was successfully unassigned."
  end

  def groupwares
    software_id = params[:software_id]
    # Fetch groupwares associated with the current project and the selected software_id
    groupwares = @project.groupwares
      .joins(:softwares)
      .where(softwares: { id: software_id })
      .distinct
    render json: groupwares
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_project
    @project = Project.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def project_params
    params.require(:project).permit(:title, :description, :start_date, :content, :client_id, :user_id, :image, :special,
                                    software_ids: [], groupware_ids: [])
  end
end
