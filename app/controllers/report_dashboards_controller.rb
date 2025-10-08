class ReportDashboardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_dashboard, only: %i[show edit update destroy apply]

  def index
    @dashboards = current_user.defect_filters.report_dashboards.active.order(:name)
  end

  def new
    @dashboard = current_user.defect_filters.build(filter_type: 'report', is_dashboard: true)
  end

  def create
    @dashboard = current_user.defect_filters.build(dashboard_params)
    @dashboard.filter_type = 'report'
    @dashboard.is_dashboard = true
    @dashboard.created_by = current_user

    if @dashboard.save
      redirect_to report_dashboards_path, notice: 'Dashboard saved successfully.'
    else
      render :new
    end
  end

  def show
    # Apply the dashboard filters and redirect to reports
    report_params = @dashboard.to_report_params.merge(commit: 'Apply')
    redirect_to reports_path(report_params)
  end

  def apply
    # Apply dashboard and show results immediately
    report_params = @dashboard.to_report_params.merge(commit: 'Apply')
    redirect_to reports_path(report_params)
  end

  def edit; end

  def update
    if @dashboard.update(dashboard_params.merge(modified_by: current_user))
      redirect_to report_dashboards_path, notice: 'Dashboard updated successfully.'
    else
      render :edit
    end
  end

  def destroy
    @dashboard.update(archive_status: true, deleted_by: current_user, deleted_on: Time.current)
    redirect_to report_dashboards_path, notice: 'Dashboard deleted successfully.'
  end

  private

  def set_dashboard
    @dashboard = current_user.defect_filters.report_dashboards.active.find(params[:id])
  end

  def dashboard_params
    params.require(:defect_filter).permit(
      :name, :product_id, :is_dashboard,
      filters: {},
      chart_config: {}
    ).tap do |whitelisted|
      # Handle the filters from reports form
      whitelisted[:filters] = JSON.parse(params[:defect_filter][:filters]) if params[:defect_filter] && params[:defect_filter][:filters].is_a?(String)
    end
  end
end
