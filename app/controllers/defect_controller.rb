class DefectController < ApplicationController
  before_action :set_defect, only: %i[show edit update destroy add_defect]

  def index
    @defect = Defect.all
    @defect = @defect.joins(:users).where(users: { id: current_user.id }) unless current_user.has_any_role?(:admin, :observer)

    @products_in_qa = Product.with_quality_assurance_status
      .includes(:statuses, :client) # Add others as needed
      .order(updated_at: :desc)

    # Pagination
    @per_page = 12
    @page = (params[:page] || 1).to_i
    @total_pages = (@products_in_qa.count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, @products_in_qa.count].min
    @total_count = @products_in_qa.count

    @products_in_qa = @products_in_qa.offset((@page - 1) * @per_page).limit(@per_page)
  end

  def show
    return if current_user.has_any_role?(:admin, :observer) || @defect.users.include?(current_user)

    redirect_to defect_index_path, alert: 'You are not authorized to view this defect.' and return

    @defect = Defect.find(params[:id])
  end

  # def new
  #   @defect = Defect.new
  #   @parents = QaModule.where(parent_id: nil) # only top-level modules
  #   @qa_modules = QaModule.where(parent_id: nil)
  #   @banking_types = BankingType.all
  #   @users = User.with_agent_project_manager_role.order(:first_name, :last_name)
  # end

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

    if @defect.save
      redirect_to @defect, notice: 'Defect created successfully'
    else
      # Reload collections if save fails
      @qa_modules = QaModule.where(parent_id: nil)
      @banking_types = BankingType.all
      @users = User.with_agent_project_manager_role.order(:first_name, :last_name)
      @submodules = @defect.qa_module&.submodules || []
      render :new
    end
  end

  def edit
    @defect = Defect.find(params[:id])
    @product = @defect.product || Product.includes(:client, :groupwares, :statuses)
      .find_by(statuses: { name: 'Quality Assurance' }) ||
               Product.includes(:client, :groupwares).first

    @products_and_clients_defects = Product.includes(:client, :groupwares, :statuses)
      .select { |product| product.statuses.any? { |status| status.name == 'Quality Assurance' } }
      .map do |product|
        client_name = product.client&.name || 'No Client'
        groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
        ["#{client_name} - #{groupware_names}", product.id]
      end

    # Load existing attachments
    @existing_images = @defect.images
    @existing_videos = @defect.videos
  end

  # def create
  #   @defect = Defect.new(defect_params)
  #   audit_on_create(@defect)

  #   respond_to do |format|
  #     if @defect.save
  #       activity('user_activity')
  #         .caused_by(current_user)
  #         .performed_on(@defect)
  #         .event('defect.create')
  #         .with_properties(product_id: @defect.product_id)
  #         .log("Created Defect ##{@defect.id}")
  #       format.html { redirect_to defect_index_path, notice: 'Defect was successfully created.' }
  #     else
  #       format.html { render :new, status: :unprocessable_entity }
  #     end
  #   end
  # end

  def update
    audit_on_update(@defect)
    if @defect.update(defect_params)
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.update')
        .with_properties(product_id: @defect.product_id)
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

  # app/controllers/defects_controller.rb
  def get_submodules
    parent_module = QaModule.find(params[:module_id])
    @submodules = parent_module.submodules.active
    render json: @submodules
  end

  private

  def load_resources
    @qa_modules = QaModule.modules.active # Only parent modules
    @banking_types = BankingType.active
    @users = User.with_agent_project_manager_role.order(:first_name, :last_name)
  end

  def load_form_collections
    @qa_modules = QaModule.where(parent_id: nil)
    @banking_types = BankingType.active
    @users = User.with_agent_project_manager_role.order(:first_name, :last_name)
    # Initialize submodules if editing an existing defect
    @submodules = if @defect.persisted? && @defect.qa_module_id
                    QaModule.where(parent_id: @defect.qa_module_id).active
                  else
                    []
                  end
  end

  def set_defect
    @defect = Defect.find(params[:id])
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
      user_ids: []
    )
  end
end
