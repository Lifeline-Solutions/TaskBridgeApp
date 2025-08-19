class MilestonesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_milestone

  def toggle_paid
    was_paid = @milestone.paid?

    if @milestone.update(paid: params[:paid] == '1')
      @product = @milestone.product

      # Resolve the assigned user (adjust these fallbacks to match your associations)
      assigned_user = @milestone.try(:assigned_user) || @milestone.try(:user) || @product.user

      # Send email only when transitioning from unpaid -> paid
      UserMailer.milestone_payment_toggled(current_user, @milestone, @product, assigned_user).deliver_later if @milestone.paid? && !was_paid

      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@milestone)
        .event('milestone.toggle_paid')
        .with_properties(paid: @milestone.paid, status: @milestone.status&.name, product_id: @milestone.product_id)
        .log('Milestone payment toggled')
    end

    respond_to do |format|
      format.html { redirect_back fallback_location: product_path(@milestone.product), notice: "Milestone with status '#{@milestone.status&.name}' is now paid." }
      format.js
    end
  end

  def new; end

  private

  def set_milestone
    @milestone = Milestone.includes(product: :client).find(params[:id])
  end
end
