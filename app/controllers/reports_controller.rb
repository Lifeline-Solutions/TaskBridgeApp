# app/controllers/reports_controller.rb
class ReportsController < ApplicationController
  before_action :authenticate_user!

  def index
    @products = Product.includes(:client, :groupwares, :statuses)
      .select do |product|
      product.statuses.any? { |status| ['Pre Quality Assurance', 'End Of Quality Assurance'].include?(status.name) } &&
        Defect.published.where(product_id: product.id).exists?
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

    @defects_per_status = defects_scope
      .joins(:statuses)
      .group('statuses.id', 'statuses.name')
      .count

    # Count retests per defect and sum for total
    @defects_per_retest = defects_scope.where('retest_count > 0').sum(:retest_count)
  end
end
