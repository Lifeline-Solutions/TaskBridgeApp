class ClientController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client, only: %i[show edit update]
  load_and_authorize_resource

  def index
    @client = Client.all
    @client = if params[:query].present?
                @client.where(
                  'name ILIKE ? OR email ILIKE ? OR phone ILIKE ? OR address ILIKE ? OR client_contact_person ILIKE ? OR
                   client_contact_phone_number ILIKE ? OR client_contact_person_email ILIKE ?', "%#{params[:query]}%",
                  "%#{params[:query]}%", "%#{params[:query]}%", "%#{params[:query]}%", "%#{params[:query]}%",
                  "%#{params[:query]}%", "%#{params[:query]}%"
                )
              else
                @client.order('created_at DESC')
              end

    @per_page = 10
    @page = (params[:page] || 1).to_i
    @total_pages = (@client.count / @per_page.to_f).ceil
    @client = @client.offset((@page - 1) * @per_page).limit(@per_page)
  end

  def new
    @client = Client.new
  end

  def create
    @client = Client.new(client_params)
    @client.user_id = current_user.id
    audit_on_create(@client)

    respond_to do |format|
      if current_user.has_role?(:admin)
        if @client.save
          activity('user_activity')
            .caused_by(current_user)
            .performed_on(@client)
            .event('client.create')
            .log('Client created')
          format.html { redirect_to client_index_path, notice: 'Client was successfully created.' }
        else
          format.html { render :new, status: :unprocessable_entity }
        end
      else
        format.html do
          render :new, status: :unprocessable_entity, notice: 'You are not authorized to create a client.'
        end
      end
    end
  end

  def show; end

  def edit; end

  def update
    audit_on_update(@client)
    respond_to do |format|
      if @client.update(client_params)
        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@client)
          .event('client.update')
          .log('Client updated')
        format.html { redirect_to client_index_path, notice: 'Client was successfully updated.' }
      else
        format.html { render 'edit', status: :unprocessable_entity }
      end
    end
  end

  def destroy
    if audit_soft_delete(@client)
      # soft-deleted
    else
      @client.destroy
    end
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@client)
      .event('client.destroy')
      .log('Client removed')
    respond_to do |format|
      format.html { redirect_to client_index_path, notice: 'Client was successfully destroyed.' }
    end
  end

  private

  def set_client
    @client = Client.find(params[:id])
  end

  def client_params
    params.require(:client).permit(:name, :email, :phone, :address, :client_contact_person,
                                   :client_contact_phone_number, :client_contact_person_email, :country_code)
  end
end
