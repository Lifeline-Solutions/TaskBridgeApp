# QA Dashboards Controller - Manages dashboards with embedded widgets
class QaDashboardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_dashboard, only: %i[show edit update destroy]

  def index
    @dashboards = current_user.dashboards.active.includes(:defect_filter)
  end

  def new
    @dashboard = Dashboard.new
    @saved_filters = current_user.defect_filters.active
  end

  def create
    @dashboard = current_user.dashboards.build(dashboard_params)
    @dashboard.created_by = current_user
    @dashboard.modified_by = current_user

    if @dashboard.save
      redirect_to qa_dashboard_path(@dashboard), notice: 'Dashboard created successfully.'
    else
      @saved_filters = current_user.defect_filters.active
      render :new, status: :unprocessable_entity
    end
  end

  def show
    # Initialize product filter variables
    @selected_product_ids = params[:product_id] || []

    # Load products with QA statuses (similar to reports_controller approach)
    products = Product.qa_projects.active.includes(:client, :groupwares)
    @product_options = products.map do |product|
      client_name = product.client&.name || 'No Client Assigned'
      groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
      ["#{client_name} - #{groupware_names}", product.id]
    end

    # Determine which products to filter by:
    # 1. If user selected products via dropdown, use those
    # 2. Otherwise, use the filter's associated product_id (default view)
    # 3. If neither exists, show all products (legacy behavior)
    product_ids_to_filter = if @selected_product_ids.any?
                              @selected_product_ids
                            elsif @dashboard.defect_filter.product_id.present?
                              [@dashboard.defect_filter.product_id]
                            else
                              []
                            end

    # Generate automatic charts for active filter parameters with product filtering
    result = DashboardDataGenerator.new(@dashboard, product_ids: product_ids_to_filter).generate
    @defects = result[:defects]
    @charts = result[:charts]
    @total_count = result[:total_count]
    @filter_params = @dashboard.defect_filter.sanitized_filters

    # Resolve current project names for display
    @current_project_names = resolve_project_names(product_ids_to_filter)

    # Debug: Log active parameters
    Rails.logger.debug '=== DASHBOARD DEBUG ==='
    Rails.logger.debug "Filter ID: #{@dashboard.defect_filter.id}"
    Rails.logger.debug "Filter's product_id: #{@dashboard.defect_filter.product_id}"
    Rails.logger.debug "Selected product IDs from UI: #{@selected_product_ids.inspect}"
    Rails.logger.debug "Product IDs used for filtering: #{product_ids_to_filter.inspect}"
    Rails.logger.debug "Active Filter Parameters: #{@dashboard.active_filter_parameters.inspect}"
    Rails.logger.debug "Sanitized Filters: #{@filter_params.inspect}"
    Rails.logger.debug "Charts Generated: #{@charts.keys.inspect}"
    Rails.logger.debug '======================='

    # Legacy widget data (if widgets exist)
    @widget_data = {}
    @dashboard.widgets.each_with_index do |_widget, index|
      @widget_data[index] = @dashboard.generate_widget_data(index)
    end
  end

  def edit
    @saved_filters = current_user.defect_filters.active
  end

  def update
    @dashboard.modified_by = current_user

    if @dashboard.update(dashboard_params)
      redirect_to qa_dashboard_path(@dashboard), notice: 'Dashboard updated successfully.'
    else
      @saved_filters = current_user.defect_filters.active
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @dashboard.update(deleted_on: Time.current, deleted_by: current_user)
    redirect_to qa_dashboards_path, notice: 'Dashboard deleted successfully.'
  end

  private

  def set_dashboard
    @dashboard = current_user.dashboards.find(params[:id])
  end

  def dashboard_params
    params.require(:dashboard).permit(
      :name,
      :description,
      :defect_filter_id,
      :auto_refresh_interval,
      widgets: %i[name group_by_field visualization_type position]
    )
  end

  def resolve_project_names(product_ids)
    return 'All Products' if product_ids.empty?

    # Fetch products based on IDs
    products = Product.where(id: product_ids).includes(:client, :groupwares)

    if products.empty?
      # Fallback to dashboard filter's single product if no products found by IDs
      if @dashboard.defect_filter.product_id.present?
        fallback_product = Product.find_by(id: @dashboard.defect_filter.product_id)
        return fallback_product&.document_name || 'All Products'
      end
      'All Products'
    elsif products.one?
      # Single product - show full name with client info
      product = products.first
      client_name = product.client&.name || 'No Client'
      groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
      "#{client_name} - #{groupware_names}"
    else
      # Multiple products - show count and summarize
      "#{products.count} Projects Selected"
    end
  end
end
