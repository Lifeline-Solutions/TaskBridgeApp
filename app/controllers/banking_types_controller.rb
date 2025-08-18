class BankingTypesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_banking_type, only: %i[show edit update destroy]

  # GET /banking_types
  def index
    @banking_types = BankingType.all.order(:name)
  end

  # GET /banking_types/1
  def show; end

  # GET /banking_types/new
  def new
    @banking_type = BankingType.new
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
      # soft-deleted
    else
      @banking_type.destroy
    end
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@banking_type)
      .event('banking_type.destroy')
      .log('BankingType removed')
    respond_to do |format|
      format.html { redirect_to banking_types_url, notice: 'Banking type was successfully deleted.' }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_banking_type
    @banking_type = BankingType.find(params[:id])
  end

  # Only allow a list of trusted parameters through.
  def banking_type_params
    params.require(:banking_type).permit(:name)
  end
end
