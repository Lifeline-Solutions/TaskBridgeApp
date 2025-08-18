class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_task
  before_action :set_message, only: %i[edit update destroy]

  def new
    @task = Task.find(params[:task_id])
    @message = @task.messages.build
  end

  def show
    @task = Task.find(params[:id])
    @message = @task.messages.build
  end

  def index
    @messages = @task.messages.includes(:author, :users).order(created_at: :desc)
  end

  def create
    @message = @task.messages.build(message_params)
    @message.author = current_user
    audit_on_create(@message)
    if @message.save
      current_user.add_role :creator, @message
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@message)
        .event('message.create')
        .with_properties(task_id: @task.id, product_id: @task.product_id)
        .log("Created Message ##{@message.id} on Task ##{@task.id}")
      selected_users = User.where(id: message_params[:user_ids])
      selected_users.each do |message_user|
        UserMailer.new_message_email(message_user, @message, current_user).deliver_later
      end
      @messages = @task.messages.includes(:author, :users).order(created_at: :desc)
      render :index, notice: 'Message was successfully assigned.'
    else
      @messages = @task.messages.includes(:author, :users).order(created_at: :desc)
      flash.now[:alert] = 'Failed to create the message.'
      render :index, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    audit_on_update(@message)
    if @message.update(message_params)
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@message)
        .event('message.update')
        .with_properties(task_id: @task.id)
        .log("Updated Message ##{@message.id}")
      redirect_to product_task_path(@product, @task), notice: 'Message was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    if audit_soft_delete(@message)
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@message)
        .event('message.soft_delete')
        .with_properties(task_id: @task.id)
        .log("Soft-deleted Message ##{@message.id}")
    else
      @message.destroy
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@message)
        .event('message.destroy')
        .with_properties(task_id: @task.id)
        .log("Destroyed Message ##{@message.id}")
    end
    redirect_to product_task_path(@task.product, @task), notice: 'Message deleted successfully.'
  end

  private

  def set_task
    @task = Task.find(params[:task_id])
    @product = @task.product
  end

  def set_message
    @message = @task.messages.find(params[:id])
  end

  def message_params
    params.require(:message).permit(:message_type, :content, :user_id, attachments: [], user_ids: [])
  end
end
