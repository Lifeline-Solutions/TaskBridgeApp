class QaModulesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_qa_module, only: %i[edit update destroy]
  before_action :set_products_and_clients_defects, only: %i[new create edit update]

  def index
    @qa_modules = if params[:product_id].present?
                    QaModule.where(product_id: params[:product_id], parent_id: nil).order(:name)
                  else
                    QaModule.where(parent_id: nil).order(:name)
                  end

    # fall back
    @qa_modules ||= QaModule.none

    if params[:module_id].present?
      @qa_module = QaModule.find(params[:module_id])

      # Base query for submodules
      submodules = QaModule.where(parent_id: @qa_module.id).order(:name)

      # Pagination setup
      @per_page = (params[:per_page] || 5).to_i
      @page = (params[:page] || 1).to_i
      @total_count = submodules.count
      @total_pages = (@total_count / @per_page.to_f).ceil
      @start_count = ((@page - 1) * @per_page) + 1
      @end_count = [@page * @per_page, @total_count].min

      # Apply pagination
      @child_modules = submodules.offset((@page - 1) * @per_page).limit(@per_page)
    else
      @qa_module = nil
      @child_modules = []
      @page = 1
      @total_pages = 1
    end
  end

  def show
    @qa_module = QaModule.find(params[:id])
    @child_modules = QaModule.where(parent_id: @qa_module.id).order(:name)
  end

  def new
    @qa_module = QaModule.new
    @products_and_clients_defects = set_products_and_clients_defects

    if params[:product_id].present?
      # Pre-select the product on the new form
      @qa_module.product_id = params[:product_id]

      # Parent modules for that product only
      @parents = QaModule.where(product_id: params[:product_id], parent_id: nil).order(:name)
    else
      @parents = []
    end
  end

  def create
    @qa_module = QaModule.new(name: params[:qa_module][:name], product_id: params[:qa_module][:product_id])
    audit_on_create(@qa_module)
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@qa_module)
      .event('qa_module.create')
      .log('QA Module created')

    if params[:qa_module][:parent_id].present?
      parent = QaModule.find_by(id: params[:qa_module][:parent_id])
      @qa_module.parent_id = parent.id if parent
    end

    if @qa_module.save
      respond_to do |format|
        format.html { redirect_to qa_modules_path(product_id: @qa_module.product_id), notice: 'Module created successfully.' }
        format.turbo_stream
      end
    else
      @parents = QaModule.where(parent_id: nil)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @parents = QaModule.where(parent_id: nil)
  end

  def update
    audit_on_update(@qa_module)
    parent_id = params[:qa_module][:parent_id].presence

    if @qa_module.update(name: params[:qa_module][:name], parent_id: parent_id, product_id: params[:qa_module][:product_id])
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@qa_module)
        .event('qa_module.update')
        .with_properties(parent_id: parent_id)
        .log('QA Module updated')
      redirect_to qa_modules_path, notice: 'Module was successfully updated.'
    else
      @parents = QaModule.where.not(id: @qa_module.id)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if audit_soft_delete(@qa_module)
      redirect_to qa_modules_path, notice: 'Module deleted.'
    else
      @qa_module.destroy
      redirect_to qa_modules_path, notice: 'Module destroyed.'
    end
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@qa_module)
      .event('qa_module.destroy')
      .log('QA Module removed')
  end

  def submodules
    @submodules = QaModule.where(parent_id: params[:id])
    render json: @submodules.select(:id, :name)
  end

  private

  def set_products_and_clients_defects
    Product.includes(:client, :groupwares, :statuses)
      .select do |product|
        product.statuses.any? { |s| ['Pre Quality Assurance', 'End Of Quality Assurance'].include?(s.name) }
      end
      .map do |product|
        client_name = product.client&.name || 'No Client'
        groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
        ["#{client_name} - #{groupware_names}", product.id]
      end
  end

  def set_qa_module
    @qa_module = QaModule.find(params[:id])
  end

  def qa_module_params
    params.require(:qa_module).permit(:name, :product_id, :parent_id)
  end
end
