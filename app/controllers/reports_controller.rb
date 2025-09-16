class ReportsController < ApplicationController
  before_action :authenticate_user!
  # ruby

  def index
    @products = Product.includes(:client, :groupwares, :statuses)
      .select do |product|
      product.statuses.any? do |status|
        ['Pre Quality Assurance', 'End Of Quality Assurance'].include?(status.name)
      end
    end
    @product_options = @products.map do |product|
      client_name = product.client&.name || 'No Client Assigned'
      groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
      ["#{client_name} - #{groupware_names}", product.id]
    end

    product_id = params[:product_id]
    defects_scope = Defect.published
    defects_scope = defects_scope.where(product_id: product_id) if product_id.present?

    @defects_per_creator = defects_scope
      .joins(:creator)
      .group('users.id', 'users.first_name', 'users.last_name')
      .count

    # Add this block for defects per status
    @defects_per_status = defects_scope
      .joins(:statuses)
      .group('statuses.id', 'statuses.name')
      .count
  end
end
