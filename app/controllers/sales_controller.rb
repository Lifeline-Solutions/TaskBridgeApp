class SalesController < ApplicationController
  before_action :authenticate_user!

  def index
    @product = Product.includes(softwares: :groupwares)
    @used_statuses = @product.map { |p| p.statuses.first&.name }.compact.uniq
  end
end
