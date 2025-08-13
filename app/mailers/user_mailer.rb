# app/mailers/user_mailer.rb
class UserMailer < ApplicationMailer
  default from: 'cspm@craftsilicon.com'
  # From Project Controller
  def assignment_email(user, project, current_user, assigned_user)
    @user = user
    @project = project
    @current_user = current_user
    @assigned_user = assigned_user
    @url = project_url(@project)
    mail(to: @user.email, subject: 'Support Desk Assignment')
  end

  def mention_notification(user, comment)
    @user = user
    @comment = comment
    mail(to: @user.email, subject: 'You were mentioned in a comment')
  end
  # From Ticket Controller create

  def create_ticket_email(ticket, current_user, assigned_user, project)
    @ticket = ticket
    @current_user = current_user
    @assigned_user = assigned_user
    @project = project
    @url = project_ticket_url(@ticket.project, @ticket)
    recipient_email = assigned_user.respond_to?(:email) ? assigned_user.email : assigned_user
    mail(to: recipient_email, subject: "A new ticket has been created with Ticket ID #{@ticket.unique_id}.")
  end

  def edit_ticket_email(user, ticket, current_user, assigned_user, project)
    @user = user
    @ticket = ticket
    @current_user = current_user
    @assigned_user = assigned_user
    @project = project
    @url = project_ticket_url(@ticket.project, @ticket)
    mail(to: @assigned_user.email, subject: "A ticket with Ticket ID #{@ticket.unique_id} has been edited.")
  end

  # From Ticket Controller create
  def ticket_assignment_email(user, project, ticket, current_user, assigned_user)
    @user = user
    @ticket = ticket
    @current_user = current_user
    @project = project
    @assigned_user = assigned_user
    @url = project_ticket_url(@ticket.project, @ticket)
    mail(to: @user.email, subject: "Ticket assigned with Ticket ID #{@ticket.unique_id}.")
  end

  # From Ticket Controller

  def status_update_email(user, ticket, current_user, project)
    @user = user
    @ticket = ticket
    @current_user = current_user
    @project = project
    @url = project_ticket_url(@ticket.project, @ticket)
    mail(to: @user.email, subject: "Status update for Ticket ID #{@ticket.unique_id}.")
  end

  # From Product Controller

  def assign_product_email(user, product, current_user, assigned_user)
    @user = user
    @product = product
    @current_user = current_user
    @assigned_user = assigned_user
    @url = product_url(@product)
    mail(to: @user.email, subject: 'Product Assignment')
  end

  # From Task Controller
  def task_assignment_email(user, task, current_user, assigned_user)
    @user = user
    @task = task
    @current_user = current_user
    @assigned_user = assigned_user
    @url = product_tasks_url(@task.product, @task)
    mail(to: @user.email, subject: 'You have been assigned to a new task')
  end

  def add_state_email(user, task, current_user)
    @user = user
    @task = task
    @current_user = current_user
    @url = product_task_url(@task.product, @task)
    mail(to: @user.email, subject: 'Task State Updated')
  end

  def new_comment_email(user, comment, current_user, project, ticket)
    @user = user
    @comment = comment
    @current_user = current_user
    @project = project
    @ticket = ticket
    @url = project_ticket_url(@comment.ticket.project, @comment.ticket)
    mail(to: @user.email, subject: "Root Cause Analysis for Ticket ID #{@comment.ticket.unique_id}.")
  end

  def bug_mailer_email(user, bug, current_user, assigned_user)
    @user = user
    @bug = bug
    @current_user = current_user
    @assigned_user = assigned_user
    @url = product_bug_url(@bug.product, @bug)
    mail(to: @user.email, subject: 'Bug Assignment')
  end

  def issue_created_email(user, issue, project, ticket, current_user)
    @user = user
    @issue = issue
    @current_user = current_user
    @project = project
    @ticket = ticket
    @url = project_ticket_url(@issue.project, @issue.ticket)
    mail(to: @user.email, subject: "New Messsage Created for Ticket ID #{@issue.ticket.unique_id}")
  end

  def mention_user_in_issue(user, issue, sender, project, ticket)
    @user = user
    @issue = issue
    @sender = sender # This is the current_user passed from the controller
    @project = project
    @ticket = ticket
    @url = project_ticket_url(@project, @ticket) # Generate the URL for the ticket

    mail(
      to: @user.email,
      subject: "New Comment on Ticket ##{@ticket.unique_id} With Subject #{@ticket.subject}"
    )
  end

  def cease_fire_report_email(email, contact_person, client_name, encoded_xlsx_data)
    return if email.blank? # Skip sending if email is blank

    @contact_person = contact_person
    @client_name = client_name

    attachments["ticket_status_report_#{client_name}_#{Date.today}.xlsx"] = Base64.decode64(encoded_xlsx_data)
    mail(to: email, subject: "Cease Fire Report for #{client_name}")
  end

  # Report email for all user
  def daily_ticket_email(user, tickets, mail_options = {})
    @user = user
    @tickets = tickets

    mail(to: @user.email, cc: mail_options[:cc], subject: "Daily Ticket Report for #{@user.name}") do |format|
      format.html { render 'daily_ticket_email' }
      format.text { render plain: "Daily Ticket Report for #{@user.name}" }
    end
  end

  def morning_ticket_email(user, tickets, mail_options = {})
    @user = user
    @tickets = tickets

    mail(to: @user.email, cc: mail_options[:cc], subject: "Start of Day Ticket Report for #{@user.name}") do |format|
      format.html { render 'morning_ticket_email' }
      format.text { render plain: "Morning Ticket Report for #{@user.name}" }
    end
  end

  def finance_sales_email(product, assigned_user, current_user)
    @product = product
    @assigned_user = assigned_user
    @current_user = current_user
    @url = product_url(@product)
    mail(to: @assigned_user.email, subject: "Project Payment Status for #{@product.client.name} for #{@product.groupwares.map(&:name).join(', ').presence} milestone ") do |format|
      format.html { render 'finance_sales_email' }
      format.text { render plain: "Project Payment Status for #{@product.client.name}, for #{@product.groupwares.map(&:name).join(', ').presence} for milestone " }
    end
  end
end
