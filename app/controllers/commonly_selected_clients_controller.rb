class CommonlySelectedClientsController < ApplicationController
  before_action :authenticate_user!

  def index
    @common_clients = current_user.common_clients
    @available_clients = Client.where.not(id: @common_clients.pluck(:id))

    render partial: 'commonly_selected_clients/manage', formats: [:html]
  end

  def create
    @common_client = current_user.commonly_selected_clients.build(client_id: params[:client_id])
    @common_clients = current_user.common_clients
    @available_clients = Client.where.not(id: @common_clients.pluck(:id))
    audit_on_create(@common_client)
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@common_client)
      .event('commonly_selected_client.create')
      .with_properties(client_id: params[:client_id])
      .log('Added client to common list')

    if @common_client.save
      flash.now[:notice] = 'Client added to your common list.'
    else
      flash.now[:alert] = @common_client.errors.full_messages.to_sentence
    end

    render partial: 'commonly_selected_clients/manage', formats: [:html]
  end

  def remove_client
    @common_client = current_user.commonly_selected_clients.find_by(client_id: params[:client_id])
    if @common_client
      if audit_soft_delete(@common_client)
        # soft-deleted
      else
        @common_client.destroy
      end
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@common_client)
        .event('commonly_selected_client.destroy')
        .with_properties(client_id: params[:client_id])
        .log('Removed client from common list')
    end

    @common_clients = current_user.common_clients
    @available_clients = Client.where.not(id: @common_clients.pluck(:id))
    flash.now[:notice] = 'Client removed from your common list.'

    render partial: 'commonly_selected_clients/manage', formats: [:html]
  end

  def ids
    @common_clients = current_user.common_clients.order(:name)
    render json: {
      client_ids: @common_clients.pluck(:id),
      client_names: @common_clients.pluck(:name, :id)
    }
  end
end
