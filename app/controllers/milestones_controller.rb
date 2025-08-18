class MilestonesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_milestone

  def toggle_paid
    @milestone.update(paid: params[:paid] == '1')
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@milestone)
      .event('milestone.toggle_paid')
      .with_properties(paid: @milestone.paid, status: @milestone.status&.name, product_id: @milestone.product_id)
      .log('Milestone payment toggled')
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
