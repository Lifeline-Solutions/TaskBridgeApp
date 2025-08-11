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

  def new
    @defect = Defect.new

    # Pick the first product in QA status
    @product = Product.includes(:client, :groupwares, :statuses)
      .find_by(statuses: { name: 'Quality Assurance' })

    # Fallback: If no QA product found, just pick first product
    @product ||= Product.includes(:client, :groupwares).first

    # Dropdown options for product selection
    @products_and_clients_defects = Product.includes(:client, :groupwares, :statuses)
      .select { |product| product.statuses.any? { |status| status.name == 'Quality Assurance' } }
      .map do |product|
        client_name = product.client&.name || 'No Client'
        groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
        ["#{client_name} - #{groupware_names}", product.id]
      end
  end

  def edit
    @products_and_clients_defects = Product.includes(:client, :groupwares, :statuses)
      .select { |product| product.statuses.any? { |status| status.name == 'Quality Assurance' } }
      .map do |product|
      client_name = product.client&.name || 'No Client'
      groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
      ["#{client_name} - #{groupware_names}", product.id]
    end
  end

  def create
    @defect = Defect.new(defect_params)

    respond_to do |format|
      if @defect.save
        format.html { redirect_to defect_index_path, notice: 'Defect was successfully created.' }
      else
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def update
    if @defect.update(defect_params)
      redirect_to @defect, notice: 'Defect was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    @defect.destroy
    redirect_to defects_url, notice: 'Defect was successfully destroyed.'
  end

  # add a user to the defect
  def add_defect
    if @defect.users.include?(User.find(params[:user_id]))
      redirect_to @defect, notice: 'User has already been assigned.'
    else
      user = User.find(params[:user_id])
      @defect.users << user
      redirect_to defect_path(@defect), notice: "#{user.name}  was successfully assigned."
    end
  end

  def remove_defect
    @defect = Defect.find(params[:id])
    user = User.find(params[:user_id])
    @defect.users.delete(user)
    redirect_to defect_path(@defect), notice: "#{user.name} was successfully removed from the defect."
  end

  private

  def set_defect
    @defect = Defect.find(params[:id])
  end

  def defect_params
    params.require(:defect).permit(:name, :description, :start_date, :end_date, :product_id, :user_id,
                                   :submodule, :issue, :priority, :summary, :software_id, :groupware_id, :script_id, :label)
  end
end