class RatingsController < ApplicationController
  before_action :set_ticket
  before_action :authenticate_user!

  def create
    @rating = @ticket.ratings.find_or_initialize_by(user: current_user)
    @rating.assign_attributes(rating_params)
    @rating.value = rating_params[:value]
    audit_on_create(@rating)

    if @rating.save
      redirect_to project_ticket_path(@ticket.project, @ticket), notice: 'Rating submitted successfully.'
    else
      redirect_to project_ticket_path(@ticket.project, @ticket), alert: 'Failed to submit rating.'
    end
  end

  private

  def set_ticket
    @ticket = Ticket.find(params[:ticket_id])
  end

  def rating_params
    params.require(:rating).permit(:value, :comment, :user_id)
  end
end
