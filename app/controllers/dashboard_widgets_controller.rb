class DashboardWidgetsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_dashboard, only: %i[show edit update destroy refresh]

  # GET /dashboard_widgets
  # Shows all dashboards for the current user
  def index
    authorize! :read, DashboardWidget

    @dashboards = current_user.dashboard_widgets
      .active
      .ordered
      .includes(:defect_filter)

    # Load saved filters for the dashboard creation form
    @saved_filters = current_user.defect_filters.defect_filters.active.order(:name)
  end

  # GET /dashboard_widgets/:id
  # Shows a single dashboard with its data
  def show
    authorize! :read, @dashboard
    result = @dashboard.generate_data
    @defects = result[:defects]
    @charts = result[:charts]
    @total_count = result[:total_count]
  end

  # GET /dashboard_widgets/new
  def new
    authorize! :create, DashboardWidget
    @dashboard = DashboardWidget.new
    @saved_filters = current_user.defect_filters.defect_filters.active.order(:name)
  end

  # GET /dashboard_widgets/:id/edit
  def edit
    authorize! :update, @dashboard
    @saved_filters = current_user.defect_filters.defect_filters.active.order(:name)
  end

  # POST /dashboard_widgets
  def create
    authorize! :create, DashboardWidget

    @dashboard = current_user.dashboard_widgets.build(dashboard_params)
    @dashboard.created_by = current_user
    @dashboard.modified_by = current_user

    if @dashboard.save
      redirect_to dashboard_widget_path(@dashboard), notice: 'Dashboard created successfully!'
    else
      @saved_filters = current_user.defect_filters.defect_filters.active.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /dashboard_widgets/:id
  def update
    authorize! :update, @dashboard

    @dashboard.modified_by = current_user

    if @dashboard.update(dashboard_params)
      redirect_to dashboard_widget_path(@dashboard), notice: 'Dashboard updated successfully!'
    else
      @saved_filters = current_user.defect_filters.defect_filters.active.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /dashboard_widgets/:id
  def destroy
    authorize! :destroy, @dashboard

    @dashboard.deleted_by = current_user
    @dashboard.deleted_on = Time.current
    @dashboard.archive_status = true
    @dashboard.save

    redirect_to dashboard_widgets_path, notice: 'Dashboard deleted successfully!'
  end

  # POST /dashboard_widgets/:id/refresh
  # Manually refresh dashboard data
  def refresh
    authorize! :read, @dashboard

    @data = @dashboard.refresh!

    respond_to do |format|
      format.html { redirect_to dashboard_widget_path(@dashboard), notice: 'Dashboard refreshed!' }
      format.json { render json: @data }
    end
  end

  private

  def set_dashboard
    @dashboard = current_user.dashboard_widgets.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to dashboard_widgets_path, alert: 'Dashboard not found!'
  end

  def dashboard_params
    params.require(:dashboard_widget).permit(
      :name,
      :defect_filter_id,
      :refresh_interval,
      chart_config: {}
    )
  end
end
