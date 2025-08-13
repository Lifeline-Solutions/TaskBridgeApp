class MilestonesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_milestone

  def toggle_paid
    @milestone.update(paid: params[:paid] == '1')
    respond_to do |format|
      format.html { redirect_back fallback_location: product_path(@milestone.product), notice: "Milestone with status '#{@milestone.status&.name}' is now paid." }
      format.js # For remote: true handling
    end
  end

  def new; end

  private

  def set_milestone
    @milestone = Milestone.find(params[:id])
  end
end