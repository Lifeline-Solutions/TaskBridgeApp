class QaModulesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_qa_module, only: %i[edit update destroy]

  def index
    @qa_modules = QaModule.all
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
    @qa_module = QaModule.new(name: params[:qa_module][:name])

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
    # Get the parent_id from params if present
    parent_id = params[:qa_module][:parent_id].presence

    # Update attributes
    if @qa_module.update(name: params[:qa_module][:name], parent_id: parent_id)
      redirect_to qa_modules_path, notice: 'Module was successfully updated.'
    else
      @parents = QaModule.where.not(id: @qa_module.id) # Reload parents for the form
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy; end

  private

  def set_qa_module
    @qa_module = QaModule.find(params[:id])
  end

  def qa_module_params
    params.require(:qa_module).permit(:name)
  end
end
