# frozen_string_literal: true

class DefectDashboardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_dashboard, only: [:show, :edit, :update, :destroy]
  
  # GET /defect_dashboards
  def index
    @dashboards = current_user.dashboards.active.order(is_default: :desc, created_at: :desc)
  end
  
  # GET /defect_dashboards/:id
  def show
    @widgets = @dashboard.widgets.includes(:defect_filter)
  end
  
  # GET /defect_dashboards/new
  def new
    @dashboard = current_user.dashboards.build(columns: 3)
  end
  
  # GET /defect_dashboards/:id/edit  
  def edit
  end
  
  # POST /defect_dashboards
  def create
    @dashboard = current_user.dashboards.build(dashboard_params)
    @dashboard.created_by = current_user
    
    if @dashboard.save
      redirect_to defect_dashboard_path(@dashboard), notice: 'Dashboard was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  # PATCH/PUT /defect_dashboards/:id
  def update
    @dashboard.modified_by = current_user
    
    if @dashboard.update(dashboard_params)
      redirect_to defect_dashboard_path(@dashboard), notice: 'Dashboard was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  # DELETE /defect_dashboards/:id
  def destroy
    @dashboard.soft_delete!(current_user)
    redirect_to defect_dashboards_path, notice: 'Dashboard was successfully deleted.'
  end
  
  private
  
  def set_dashboard
    @dashboard = current_user.dashboards.active.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to defect_dashboards_path, alert: 'Dashboard not found.'
  end
  
  def dashboard_params
    params.require(:dashboard).permit(:name, :description, :columns, :is_default)
  end
end
