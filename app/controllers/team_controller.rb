class TeamController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team, only: %i[show edit update destroy show_team_member]
  load_and_authorize_resource

  def index
    @per_page = 10
    @page = (params[:page] || 1).to_i

    @team = if params[:query].present?
              Team.where('name ILIKE :query OR description ILIKE :query', query: "%#{params[:query]}%")
            else
              Team.all.order('created_at DESC')
            end
    # Paginate the QA products instead of defect groups

    @per_page = 10
    @page = (params[:page] || 1).to_i
    @total_pages = (@team.count / @per_page.to_f).ceil
    @team = @team.offset((@page - 1) * @per_page).limit(@per_page)
  end

  def show
    @assigned_today_counts = {}
    @team.users.each do |user|
      @assigned_today_counts[user.id] = user.tickets
        .joins(:statuses)
        .where.not(statuses: { name: %w[Closed Resolved Declined] })
        .count
    end

    @closed_today_counts = {}
    @team.users.each do |user|
      @closed_today_counts[user.id] = user.tickets
        .joins(:statuses)
        .where(statuses: { name: %w[Closed Resolved], created_at: Date.today.all_day })
        .count
    end
  end

  # show tickets assigned to the team users both open and closed and their service desk
  def show_team_member
    @user = @team.users.find(params[:user_id])
    @open_tickets = @user.tickets
      .joins(:statuses)
      .where.not(statuses: { name: %w[Closed Resolved Declined] })
      .distinct
    @closed_tickets = @user.tickets
      .joins(:statuses)
      .where(statuses: { name: %w[Closed Resolved], created_at: Date.today.all_day })
      .distinct
  end

  def new
    @team = Team.new
  end

  def create
    @team = Team.new(team_params)
    audit_on_create(@team)

    respond_to do |format|
      if @team.save
        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@team)
          .event('team.create')
          .log('Team created')
        format.html { redirect_to team_index_path, notice: 'Team was successfully created.' }
      else
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def edit; end

  def update
    audit_on_update(@team)
    respond_to do |format|
      if @team.update(team_params)
        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@team)
          .event('team.update')
          .log('Team updated')
        format.html { redirect_to team_index_path, notice: 'Team was successfully updated.' }
      else
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @team.destroy unless audit_soft_delete(@team)
    respond_to do |format|
      format.html { redirect_to team_path, notice: 'Team was successfully deleted.' }
    end
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@team)
      .event('team.destroy')
      .log('Team removed')
  end

  private

  def set_team
    @team = Team.find(params[:id])
  end

  def team_params
    params.require(:team).permit(:name, :description, user_ids: [])
  end
end
