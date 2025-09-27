class BankingTypesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_banking_type, only: %i[show edit update destroy]
  before_action :set_products_and_clients_defects, only: %i[new create edit update]

  # GET /banking_types
  def index
    @banking_types = if params[:product_id].present?
                       BankingType.where(product_id: params[:product_id]).order(:name)
                     else
                       BankingType.all.order(:name)
                     end
  end

  # GET /banking_types/1
  def show; end

  # GET /banking_types/new
  def new
    @banking_type = BankingType.new

    if params[:product_id].present?
      # Pre-select the product on the new form
      @banking_type.product_id = params[:product_id]
    end
  end

  # GET /banking_types/1/edit
  def edit; end

  # POST /banking_types
  def create
    @banking_type = BankingType.new(banking_type_params)
    audit_on_create(@banking_type)

    respond_to do |format|
      if @banking_type.save
        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@banking_type)
          .event('banking_type.create')
          .log('BankingType created')
        format.html { redirect_to banking_types_path, notice: 'Banking type was successfully created.' }
        format.json { render :show, status: :created, location: @banking_type }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @banking_type.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /banking_types/1
  def update
    audit_on_update(@banking_type)
    respond_to do |format|
      if @banking_type.update(banking_type_params)
        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@banking_type)
          .event('banking_type.update')
          .log('BankingType updated')
        format.html { redirect_to banking_types_path, notice: 'Banking type was successfully updated.' }
        format.json { render :show, status: :ok, location: @banking_type }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @banking_type.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /banking_types/1
  def destroy
    if audit_soft_delete(@banking_type)
      notice_message = 'Banking type was successfully deleted.'
    else
      @banking_type.destroy
      notice_message = 'Banking type was successfully destroyed.'
    end

    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@banking_type)
      .event('banking_type.destroy')
      .log('BankingType removed')

    redirect_to banking_types_path, notice: notice_message
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

  # Use callbacks to share common setup or constraints between actions.
  def set_banking_type
    @banking_type = BankingType.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def banking_type_params
    params.require(:banking_type).permit(:name, :product_id)
  end
end
