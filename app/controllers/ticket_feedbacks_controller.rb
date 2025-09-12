class TicketFeedbacksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project_and_ticket
  before_action :authorize_client!, only: [:create]


  private

  def set_project_and_ticket
    @project = Project.find(params[:project_id])
    @ticket = @project.tickets.find(params[:id])
  end

  def authorize_client!
    # Only the ticket owner (client) may submit the feedback
    return if @ticket.user == current_user
    redirect_to project_ticket_path(@project, @ticket), alert: "Only the ticket owner can submit feedback."
  end
end