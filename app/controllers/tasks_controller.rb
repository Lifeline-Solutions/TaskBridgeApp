class TasksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_product
  before_action :set_task, only: %i[show edit update destroy assign_user remove_task add_state]

  def index
    @tasks = @product.tasks
  end

  def new
    @task = @product.tasks.new
    @prerequisite_tasks = Task.prerequisite_tasks(@product.id)
  end

  def create
    @task = @product.tasks.new(task_params)
    @task.user = current_user
    audit_on_create(@task)

    respond_to do |format|
      if @task.save
        # Assign one or more users to the task on creation
        if (assignee_id = params.dig(:task, :user_id).presence)
          assignee = User.find_by(id: assignee_id)
          @task.users << assignee if assignee && !@task.users.include?(assignee)
        end

        current_user.add_role :creator, @task
        format.html { redirect_to product_path(@product), notice: 'Task was successfully created.' }
      else
        SafeNotifier.email(StandardError.new('Task creation failed'), context: { errors: @task.errors.full_messages, product_id: @product.id, params: params.to_unsafe_h })
        Rails.logger.error("Task creation failed: #{@task.errors.full_messages.join(', ')}")
        format.html do
          redirect_to new_product_task_path(@product), notice: 'Task was not created.'
        end
      end
    end
  end

  def show
    @task = @product.tasks.find(params[:id])
    @prerequisite_task = @task
  end

  def edit; end

  def update
    audit_on_update(@task)
    if @task.update(task_params)
      redirect_to product_path(@product), notice: 'Task was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    if audit_soft_delete(@task)
      redirect_to product_path(@product), notice: 'Task was successfully deleted.'
    else
      @task.destroy
      redirect_to product_path(@product), notice: 'Task was successfully deleted.'
    end
  end

  # Assigning User a Task

  def assign_user
    if @task.users.include?(User.find(params[:user_id]))
      redirect_to product_tasks_path(@product, @task), notice: 'User has already been assigned.'
    else
      @task = @product.tasks.find(params[:id])
      @task.user = current_user
      user = User.find(params[:user_id])
      @task.users.clear
      @task.users << user
      assigned_user = user # Sending to all users added to the product
      # Send email to the newly assigned user
      UserMailer.task_assignment_email(user, @task, current_user, assigned_user).deliver_later
      # Send email to all users tagged on the product, except the current user
      # @product.users.each do |product_user|
      #   next if product_user == current_user

      #   UserMailer.task_assignment_email(product_user, @task, current_user, assigned_user).deliver_later
      # end

      redirect_to product_task_path(@product, @task), notice: "#{assigned_user.name} was successfully assigned."
    end
  end

  def remove_task
    @task.users.delete(User.find(params[:user_id]))
    redirect_to product_task_path(@product, @task), notice: 'Task was successfully unassigned.'
  end

  def add_state
    status = Status.find_by(id: params[:status_id])

    if status.nil?
      respond_to do |format|
        format.html { redirect_to product_task_path(@product, @task), alert: 'Invalid status ID' }
      end
      return
    end

    if @task.prerequisite_task.present? && !@task.prerequisite_task.statuses.exists?(name: 'Resolved')
      return redirect_to product_task_path(@product, @task), notice: 'Cannot update. Prerequisite task is already resolved.'
    end

    @task.statuses.clear
    @task.statuses << status
    UserMailer.add_state_email(@task.user, @task, current_user).deliver_later
    redirect_to product_task_path(@product, @task), notice: 'Task status updated.'
  end

  private

  def set_product
    @product = Product.find(params[:product_id])
  end

  def set_task
    @task = @product.tasks.find(params[:id])
  end

  def task_params
    params.require(:task).permit(:name, :start_date, :end_date, :image, :file, :user_id, :priority, :tasks_id)
  end
end
