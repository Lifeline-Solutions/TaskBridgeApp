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
        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@task)
          .event('task.create')
          .with_properties(product_id: @product.id)
          .log("Created Task ##{@task.id} for Product ##{@product.id}")
        # Assign one or more users to the task on creation
        if (assignee_id = params.dig(:task, :user_id).presence)
          assignee = User.find_by(id: assignee_id)
          @task.users << assignee if assignee && !@task.users.include?(assignee)
          if assignee
            activity('user_activity')
              .caused_by(current_user)
              .performed_on(@task)
              .event('task.assign_user')
              .with_properties(user_id: assignee.id)
              .log("Assigned #{assignee&.name} to Task ##{@task.id}")
          end
        end

        current_user.add_role :creator, @task
        format.html { redirect_to product_task_path(@product, @task), notice: 'Task was successfully created.' }
      else
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

  def edit
    @prerequisite_tasks = Task.prerequisite_tasks(@product.id, @task.id)
  end

  def update
    audit_on_update(@task)
    if @task.update(task_params)
      redirect_to product_task_path(@product, @task), notice: 'Task was successfully updated.'
    else
      @prerequisite_tasks = Task.prerequisite_tasks(@product.id, @task.id)
      render :edit
    end
  end

  def destroy
    @task.destroy unless audit_soft_delete(@task)
    redirect_to product_path(@product), notice: 'Task was successfully deleted.'
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
      UserMailer.task_assignment_email(user, @task, current_user, assigned_user).deliver_later

      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@task)
        .event('task.assign_user')
        .with_properties(user_id: user.id)
        .log("Assigned #{user.name} to Task ##{@task.id}")
      assigned_user = user # Sending to all users added to the product
      # Send email to the newly assigned user
      Messaging::EmailSender
        .send_email(
          'You have been assigned to a new task',
          to: [assigned_user.email],
          actor: current_user,
          priority: :normal,
          type: 'task_assign'
        )
        .use_template(view: 'user_mailer/task_assignment_email', assigns: { user: assigned_user, task: @task, current_user:, assigned_user: })
        .set_source('task', @task.id)
        .set_party('user', assigned_user.id)
        .send(queue: true)

      redirect_to product_task_path(@product, @task), notice: "#{assigned_user.name} was successfully assigned."
    end
  end

  def remove_task
    @task.users.delete(User.find(params[:user_id]))
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@task)
      .event('task.unassign_user')
      .with_properties(user_id: params[:user_id])
      .log("Unassigned User ##{params[:user_id]} from Task ##{@task.id}")
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
      return redirect_to product_task_path(@product, @task), notice: 'Cannot update, until Prerequisite Task is Resolved.'
    end

    @task.statuses.clear
    @task.statuses << status
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@task)
      .event('task.status_update')
      .with_properties(status_id: status.id, status_name: status.name)
      .log("Updated Task ##{@task.id} status to #{status.name}")
    if @task.user&.email.present?
      Messaging::EmailSender
        .send_email(
          'Task State Updated',
          to: [@task.user.email],
          actor: current_user,
          priority: :normal,
          type: 'task_state_update'
        )
        .use_template(view: 'user_mailer/add_state_email', assigns: { user: @task.user, task: @task, current_user: })
        .set_source('task', @task.id)
        .set_party('user', @task.user.id)
        .send(queue: true)
    end
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
    params.require(:task).permit(:name, :description, :start_date, :end_date, :image, :file, :user_id, :priority, :tasks_id, :unique_task_id)
  end
end
