# frozen_string_literal: true

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
    # Get QA products (same logic as reports controller)
    # Only products with 'Pre Quality Assurance' or 'End Of Quality Assurance' status
    # and that have published defects
    @products = Product.includes(:client, :groupwares, :statuses)
      .select do |product|
      product.statuses.any? { |status| ['Pre Quality Assurance', 'End Of Quality Assurance'].include?(status.name) } &&
        Defect.published.where(product_id: product.id).exists?
    end

    # Format product options for display (same as reports)
    @product_options = @products.map do |product|
      client_name = product.client&.name || 'No Client Assigned'
      groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
      ["#{client_name} - #{groupware_names}", product.id]
    end
    
    # Handle multiple product selection - convert to array if it's a string
    product_ids = if params[:product_id].is_a?(String)
                    params[:product_id].split(',')
                  else
                    Array(params[:product_id]).reject(&:blank?)
                  end
    
    # If no products selected from params, use from saved filter
    if product_ids.empty?
      saved_product_ids = @dashboard.defect_filter.sanitized_filters['product_id']
      product_ids = Array(saved_product_ids).reject(&:blank?) if saved_product_ids.present?
    end
    
    @selected_product_ids = product_ids
    
    # Generate automatic charts for active filter parameters
    result = DashboardDataGenerator.new(@dashboard, product_ids: product_ids).generate
    @defects = result[:defects]
    @charts = result[:charts]
    @total_count = result[:total_count]
    @filter_params = @dashboard.defect_filter.sanitized_filters
    
    # Add product_id to filter params if selected
    @filter_params['product_id'] = product_ids if product_ids.any?

    # Debug: Log active parameters
    Rails.logger.debug '=== DASHBOARD DEBUG ==='
    Rails.logger.debug "Filter ID: #{@dashboard.defect_filter.id}"
    Rails.logger.debug "Selected Product IDs: #{product_ids.inspect}"
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
end
