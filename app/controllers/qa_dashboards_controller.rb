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
    # Generate automatic charts for active filter parameters
    result = DashboardDataGenerator.new(@dashboard).generate
    @defects = result[:defects]
    @charts = result[:charts]
    @total_count = result[:total_count]
    @filter_params = @dashboard.defect_filter.sanitized_filters
    
    # Debug: Log active parameters
    Rails.logger.debug "=== DASHBOARD DEBUG ==="
    Rails.logger.debug "Filter ID: #{@dashboard.defect_filter.id}"
    Rails.logger.debug "Active Filter Parameters: #{@dashboard.active_filter_parameters.inspect}"
    Rails.logger.debug "Sanitized Filters: #{@filter_params.inspect}"
    Rails.logger.debug "Charts Generated: #{@charts.keys.inspect}"
    Rails.logger.debug "======================="
    
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
