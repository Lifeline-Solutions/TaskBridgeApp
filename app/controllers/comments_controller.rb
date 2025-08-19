class CommentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project
  before_action :set_ticket
  before_action :set_comment, only: %i[destroy edit update]

  def new
    @comment = @ticket.comments.new
  end

  # app/controllers/comments_controller.rb
  def create
    @comment = @ticket.comments.new(comment_params.except(:user_ids))
    @comment.project = @project
    @comment.user = current_user
    @comment.status = @ticket.statuses.pluck('statuses.name').first
    audit_on_create(@comment)

    respond_to do |format|
      if @comment.save
        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@comment)
          .event('comment.create')
          .with_properties(ticket_id: @ticket.id, project_id: @project.id)
          .log("Created Comment ##{@comment.id} on Ticket ##{@ticket.id}")
        # Send email ONLY to explicitly selected users
        selected_users = User.where(id: comment_params[:user_ids])

        selected_users.each do |comment_user|
          next if comment_user.email.blank?

          Messaging::EmailSender
            .send_email(
              "Root Cause Analysis for Ticket ID #{@ticket.unique_id}.",
              to: [comment_user.email],
              actor: current_user,
              priority: :normal,
              type: 'comment_create'
            )
            .use_template(view: 'user_mailer/new_comment_email', assigns: { user: comment_user, comment: @comment, current_user:, project: @project, ticket: @ticket })
            .set_source('comment', @comment.id)
            .set_party('user', comment_user.id)
            .send(queue: true)
        end

        format.html { redirect_to project_ticket_path(@project, @ticket), notice: 'Comment was successfully created.' }
      else
        format.html { render 'new', status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @comment = @ticket.comments.find(params[:id])
    if audit_soft_delete(@comment)
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@comment)
        .event('comment.soft_delete')
        .with_properties(ticket_id: @ticket.id)
        .log("Soft-deleted Comment ##{@comment.id}")
    else
      @comment.destroy
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@comment)
        .event('comment.destroy')
        .with_properties(ticket_id: @ticket.id)
        .log("Destroyed Comment ##{@comment.id}")
    end
    redirect_to project_ticket_path(@project, @ticket)
  end

  def edit; end

  def update
    @comment = @ticket.comments.find(params[:id])
    @comment.project = @project
    @comment.user = current_user
    audit_on_update(@comment)

    respond_to do |format|
      if @comment.update(comment_params)
        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@comment)
          .event('comment.update')
          .with_properties(ticket_id: @ticket.id)
          .log("Updated Comment ##{@comment.id}")
        format.html { redirect_to project_ticket_path(@project, @ticket), notice: 'Comment was successfully updated.' }
      else
        format.html { render 'edit', status: :unprocessable_entity }
      end
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_ticket
    @ticket = @project.tickets.find(params[:ticket_id])
  end

  def set_comment
    @comment = @ticket.comments.find(params[:id])
  end

  def comment_params
    params.require(:comment).permit(:ticket_id, :what, :why, :content, :user_id, :project_id, user_ids: [], attachments: [])
  end
end
