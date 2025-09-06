class DefaultDefectAssigneesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_default_assignee, only: %i[destroy]

  # Render modal for selecting/changing the default assignee
  def new
    @users = User.with_agent_project_manager_role.order(:first_name, :last_name)
    @default_assignee = DefaultDefectAssignee.instance
    render layout: false
  end

  # Create or update the single global default
  def create
  user = User.find(params[:user_id])
  @default_assignee = DefaultDefectAssignee.instance

  if @default_assignee.present?
    # update existing record
    @default_assignee.user = user
    audit_on_update(@default_assignee)

    if @default_assignee.save
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@default_assignee)
        .event('default_defect_assignee.update')
        .log("Updated DefaultDefectAssignee -> #{user.name} (#{user.id})")

      redirect_to defect_index_path, notice: 'Default assignee updated.'
    else
      @users = User.with_agent_project_manager_role.order(:first_name, :last_name)
      render :new, status: :unprocessable_entity, layout: false
    end
  else
    @default_assignee = DefaultDefectAssignee.new(user: user)
    audit_on_create(@default_assignee)

    if @default_assignee.save
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@default_assignee)
        .event('default_defect_assignee.create')
        .log("Set DefaultDefectAssignee -> #{user.name} (#{user.id})")

      redirect_to defect_index_path, notice: 'Default assignee set.'
    else
      @users = User.with_agent_project_manager_role.order(:first_name, :last_name)
      render :new, status: :unprocessable_entity, layout: false
    end
  end
end


  # Soft-delete the record (audit_soft_delete used)
  def destroy
    if @default_assignee.nil?
      respond_to do |format|
        format.html { redirect_back fallback_location: defect_index_path, alert: 'No default assignee found.' }
        format.turbo_stream { head :no_content }
      end
      return
    end

    if audit_soft_delete(@default_assignee)
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@default_assignee)
        .event('default_defect_assignee.destroy')
        .log('DefaultDefectAssignee soft-deleted')

      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace('default-assignee-button', partial: 'default_defect_assignees/button') }
        format.html { redirect_back fallback_location: defect_index_path, notice: 'Default assignee cleared.' }
      end
    else
      # fallback to hard destroy (rare)
      @default_assignee.destroy
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@default_assignee)
        .event('default_defect_assignee.destroy')
        .log('DefaultDefectAssignee destroyed')

      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace('default-assignee-button', partial: 'default_defect_assignees/button') }
        format.html { redirect_back fallback_location: defect_index_path, notice: 'Default assignee cleared.' }
      end
    end
  end

  private

  def set_default_assignee
    @default_assignee = DefaultDefectAssignee.instance
  end
end
