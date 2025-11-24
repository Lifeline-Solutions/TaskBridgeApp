# frozen_string_literal: true

class WidgetsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_dashboard
  before_action :set_widget, only: [:show, :edit, :update, :destroy, :data]

  # GET /defect_dashboards/:dashboard_id/widgets/:id
  # This is called by Turbo Frame lazy loading
  def show
    @data = @widget.cached_data
    
    respond_to do |format|
      format.html do
        render partial: "widgets/#{@widget.widget_type}", 
               locals: { widget: @widget, data: @data }
      end
      format.json { render json: @data }
    end
  end

  # GET /defect_dashboards/:dashboard_id/widgets/new
  def new
    @widget = @dashboard.widgets.build(width: 1, height: 1)
    @defect_filters = current_user.defect_filters.active.defect_filters
  end

  # GET /defect_dashboards/:dashboard_id/widgets/:id/edit
  def edit
    @defect_filters = current_user.defect_filters.active.defect_filters
  end

  # POST /defect_dashboards/:dashboard_id/widgets
  def create
    @widget = @dashboard.widgets.build(widget_params)
    
    if @widget.save
      redirect_to defect_dashboard_path(@dashboard), notice: 'Widget was successfully created.'
    else
      @defect_filters = current_user.defect_filters.active.defect_filters
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /defect_dashboards/:dashboard_id/widgets/:id
  def update
    if @widget.update(widget_params)
      @widget.clear_cache
      redirect_to defect_dashboard_path(@dashboard), notice: 'Widget was successfully updated.'
    else
      @defect_filters = current_user.defect_filters.active.defect_filters
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /defect_dashboards/:dashboard_id/widgets/:id
  def destroy
    @widget.destroy
    
    respond_to do |format|
      format.html { redirect_to defect_dashboard_path(@dashboard), notice: 'Widget was successfully deleted.' }
      format.turbo_stream { render turbo_stream: turbo_stream.remove(@widget) }
    end
  end

  # GET /defect_dashboards/:dashboard_id/widgets/:id/data
  # For refreshing widget data via AJAX
  def data
    @data = @widget.fetch_widget_data
    @widget.clear_cache
    
    respond_to do |format|
      format.json { render json: @data }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          dom_id(@widget),
          partial: "widgets/#{@widget.widget_type}",
          locals: { widget: @widget, data: @data }
        )
      end
    end
  end

  private

  def set_dashboard
    @dashboard = current_user.dashboards.active.find(params[:defect_dashboard_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to defect_dashboards_path, alert: 'Dashboard not found.'
  end

  def set_widget
    @widget = @dashboard.widgets.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to defect_dashboard_path(@dashboard), alert: 'Widget not found.'
  end

  def widget_params
    params.require(:widget).permit(
      :defect_filter_id, :widget_type, :title, :position, 
      :width, :height, config: {}
    )
  end
end
