class DefectController < ApplicationController
  before_action :set_defect, only: %i[show edit update destroy add_defect add_attachments remove_attachment]

  def index
    # Base query for defects
    @defects = Defect.includes(:users, :qa_module, :submodule, :banking_type)
      .order(created_at: :desc)

    # Filter defects for non-admin users
    @defects = @defects.joins(:users).where(users: { id: current_user.id }) unless current_user.has_any_role?(:admin, :observer)

    # Pagination
    @per_page = 12
    @page = (params[:page] || 1).to_i
    @total_pages = (@defects.count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, @defects.count].min
    @total_count = @defects.count

    @defects = @defects.offset((@page - 1) * @per_page).limit(@per_page)
  end

  def show
    return if current_user.has_any_role?(:admin, :observer) || @defect.users.include?(current_user)

    redirect_to defect_index_path, alert: 'You are not authorized to view this defect.' and return

    @defect = Defect.find(params[:id])
  end

  def new
    @defect = Defect.new
    @qa_modules = QaModule.where(parent_id: nil)
    @banking_types = BankingType.all
    @users = User.with_agent_project_manager_role.order(:first_name, :last_name)
    @submodules = [] # Initialize empty array
  end

  def create
    @defect = Defect.new(defect_params)
    @defect.creator = current_user
    @defect.status ||= 'Bug' # Ensure status has a default value

    if @defect.save
      # Log successful creation
      Rails.logger.info "Defect successfully created: #{@defect.inspect}"
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.create')
        .with_properties(defect_attributes: @defect.attributes)
        .log("Created Defect ##{@defect.id}")

      redirect_to defect_index_path, notice: 'Defect was successfully created.'
    else
      # Add error messages to flash
      flash.now[:alert] = "Defect creation failed: #{@defect.errors.full_messages.join(', ')}"

      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @defect = Defect.find(params[:id])
    @qa_modules = QaModule.where(parent_id: nil)
    @banking_types = BankingType.all
    @users = User.with_agent_project_manager_role.order(:first_name, :last_name)

    # Load submodules for the current module if exists
    @submodules = @defect.qa_module ? @defect.qa_module.submodules : []
  end

  def update
    audit_on_update(@defect)

    # Collect files from either place (prefer model-scoped)
    files = []
    files += Array(params.dig(:defect, :attachments)).reject(&:blank?) if params.dig(:defect, :attachments).present?
    files += Array(params[:attachments]).reject(&:blank?) if params[:attachments].present?

    files.each { |file| @defect.attachments.attach(file) } if files.any?

    if @defect.update(defect_params)
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.update')
        .with_properties(
          defect_id: @defect.id,
          qa_module_id: @defect.qa_module_id # optional, only if you want this info
        )
        .log("Updated Defect ##{@defect.id}")

      redirect_to @defect, notice: 'Defect was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    if audit_soft_delete(@defect)
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.soft_delete')
        .log("Soft-deleted Defect ##{@defect.id}")
      redirect_to defects_url, notice: 'Defect was successfully deleted.'
    else
      @defect.destroy
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.destroy')
        .log("Destroyed Defect ##{@defect.id}")
      redirect_to defects_url, notice: 'Defect was successfully destroyed.'
    end
  end

  # add a user to the defect
  def add_defect
    if @defect.users.include?(User.find(params[:user_id]))
      redirect_to @defect, notice: 'User has already been assigned.'
    else
      user = User.find(params[:user_id])
      @defect.users << user
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.assign_user')
        .with_properties(user_id: user.id)
        .log("Assigned #{user.name} to Defect ##{@defect.id}")
      redirect_to defect_path(@defect), notice: "#{user.name}  was successfully assigned."
    end
  end

  def remove_defect
    @defect = Defect.find(params[:id])
    user = User.find(params[:user_id])
    @defect.users.delete(user)
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@defect)
      .event('defect.unassign_user')
      .with_properties(user_id: user.id)
      .log("Unassigned #{user.name} from Defect ##{@defect.id}")
    redirect_to defect_path(@defect), notice: "#{user.name} was successfully removed from the defect."
  end

  def get_submodules
    parent_module = QaModule.find(params[:module_id])
    @submodules = parent_module.submodules.active
    render json: @submodules
  end

  def add_attachments
    # Handle the file upload
    if params[:attachments].present?
      # params[:attachments] will be an array when using 'attachments[]' field name
      attachments = Array(params[:attachments]).reject(&:blank?)

      if attachments.any?
        attachments.each do |attachment|
          @defect.attachments.attach(attachment)
        end
        redirect_to defect_path(@defect), notice: "#{attachments.size} file(s) were successfully uploaded."
      else
        redirect_to defect_path(@defect), alert: 'No valid files selected.'
      end
    else
      redirect_to defect_path(@defect), alert: 'Please select at least one file to upload.'
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to defects_path, alert: 'Defect not found.'
  end

  def remove_attachment
    attachment = @defect.attachments.find(params[:attachment_id])
    attachment.purge
    redirect_to defect_path(@defect), notice: 'File was successfully removed.'
  rescue ActiveRecord::RecordNotFound
    redirect_to defects_path, alert: 'File or defect not found.'
  end

  private

  def set_defect
    defect_id = params[:defect_id] || params[:id]
    @defect = Defect.find(defect_id)
  end

  def defect_params
    params.require(:defect).permit(
      :summary,
      :content,
      :qa_module_id,
      :submodule_id,
      :banking_type_id,
      :priority,
      :groupware_id,
      :status,
      user_ids: [],
      attachments: []
    )
  end
end
