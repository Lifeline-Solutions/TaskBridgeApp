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
    @messages = @task.messages.order(created_at: 'desc')
  end

  def create
    @message = @task.messages.build(message_params)
    @message.user = current_user
    audit_on_create(@message)
    if @message.save
      current_user.add_role :creator, @message
      render :index, notice: 'Message was successfully assigned.'
    else
      flash.now[:alert] = 'Failed to create the message.'
      render :index, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    audit_on_update(@message)
    if @message.update(message_params)
      redirect_to product_task_path(@product, @task), notice: 'Message was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    if audit_soft_delete(@message)
      redirect_to product_task_path(@task.product, @task), notice: 'Message deleted successfully.'
    else
      @message.destroy
      redirect_to product_task_path(@task.product, @task), notice: 'Message deleted successfully.'
    end
  end

  private

  def set_task
    @task = Task.find(params[:task_id])
  end

  def set_message
    @message = @task.messages.find(params[:id])
  end

  def message_params
    params.require(:message).permit(:message_type, :content, attachments: [])
  end
end
