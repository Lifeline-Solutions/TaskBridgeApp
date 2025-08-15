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
        # Send email to the selected users
        selected_users = User.where(id: comment_params[:user_ids])

        selected_users.each do |comment_user|
          UserMailer.new_comment_email(comment_user, @comment, current_user, @project, @ticket).deliver_later
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
      redirect_to project_ticket_path(@project, @ticket)
    else
      @comment.destroy
      redirect_to project_ticket_path(@project, @ticket)
    end
  end

  def edit; end

  def update
    @comment = @ticket.comments.find(params[:id])
    @comment.project = @project
    @comment.user = current_user
    audit_on_update(@comment)

    respond_to do |format|
      if @comment.update(comment_params)
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
