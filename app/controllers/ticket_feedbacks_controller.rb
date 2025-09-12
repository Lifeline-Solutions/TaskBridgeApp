class TicketFeedbacksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project_and_ticket
  before_action :authorize_client!, only: [:create]

  # POST /projects/:project_id/tickets/:id/create_feedback
  def create
    rating = params.dig(:ticket_feedback, :rating).to_i
    comment_html = params.dig(:ticket_feedback, :comment)

    begin
      feedback = TicketRecordFeedbackService.new(
        ticket: @ticket,
        actor: current_user,
        rating: rating,
        comment_html: comment_html
      ).call

      # log system activity (controller-level)
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@ticket)
        .event('ticket.client_feedback')
        .with_properties(rating: feedback.rating, feedback_id: feedback.id)
        .log("Client feedback recorded for Ticket ##{@ticket.id}")

      respond_to do |format|
        format.html { redirect_to project_ticket_path(@project, @ticket), notice: "Thank you — your feedback was recorded." }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("modal", partial: "tickets/modal_empty"),
            turbo_stream.replace("ticket_feedback_count_#{@ticket.id}", partial: "tickets/partials/feedback_count", locals: { ticket: @ticket }),
            turbo_stream.append("ticket_feedbacks_list_#{@ticket.id}", partial: "tickets/partials/feedback_row", locals: { feedback: feedback })
          ]
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      @feedback = e.record
      respond_to do |format|
        format.html do
          flash.now[:alert] = "Could not save feedback: #{@feedback.errors.full_messages.join(', ')}"
          render 'tickets/show', status: :unprocessable_entity
        end
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "modal",
            partial: "tickets/feedback_modal",
            locals: { ticket: @ticket, feedback: @feedback }
          ), status: :unprocessable_entity
        end
      end
    rescue => e
      Rails.logger.error("TicketFeedbacks#create: #{e.message}")
      redirect_to project_ticket_path(@project, @ticket), alert: "Could not save feedback."
    end
  end

  private

  def set_project_and_ticket
    @project = Project.find(params[:project_id])
    @ticket = @project.tickets.find(params[:id])
  end

  def authorize_client!
    # Allow any user with the client role to submit feedback
    return if current_user.has_role?(:client)

    redirect_to project_ticket_path(@project, @ticket),
                alert: "Only clients can submit feedback."
  end
end