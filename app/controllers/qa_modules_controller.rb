class QaModulesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_qa_module, only: %i[edit update destroy]
  before_action :set_products_and_clients_defects, only: %i[new create edit update]

  def index
    # Only parent (top-level) modules for the dropdown
    @qa_modules = QaModule.where(parent_id: nil).order(:name)

    if params[:module_id].present?
      @qa_module = QaModule.find(params[:module_id])
      @child_modules = QaModule.where(parent_id: @qa_module.id).order(:name)
    else
      @qa_module = nil
      @child_modules = []
    end
  end

  def show
    @qa_module = QaModule.find(params[:id])
    @child_modules = QaModule.where(parent_id: @qa_module.id).order(:name)
  end

  def new
    @qa_module = QaModule.new
    @parents = QaModule.where(parent_id: nil) # Only top-level modules
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
        format.html { redirect_to qa_modules_path, notice: 'Module created successfully.' }
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
    @products_and_clients_defects = Product.includes(:client, :groupwares, :statuses)
      .select do |product|
        product.statuses.any? { |status| ['Pre Quality Assurance', 'End Of Quality Assurance'].include?(status.name) }
      end.map do |product|
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
