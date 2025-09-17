class DefectFailureReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_defect
  before_action :authorize_view!

  def index
    @reports = @defect.defect_failure_reports.visible.order(retest_number: :asc)
    respond_to do |format|
      format.html
      format.json { render json: @reports.as_json(only: %i[id retest_number captured_at created_at]) }
    end
  end

  def show
    @report = @defect.defect_failure_reports.find(params[:id])
  end

  private

  def set_defect
    if params[:defect_id].present?
      @defect = Defect.find(params[:defect_id])
    elsif params[:id].present?
      report = DefectFailureReport.find_by(id: params[:id])
      @defect = report&.defect
    else
      head :bad_request
    end
  end

  def authorize_view!
    return if current_user.has_role?(:qa) || current_user.has_role?(:hod) || current_user.has_role?(:admin)

    render plain: 'Not authorized', status: :forbidden
  end
end
