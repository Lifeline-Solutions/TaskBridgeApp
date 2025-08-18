class IssuesController < ApplicationController
  include ActionView::RecordIdentifier
  before_action :set_project
  before_action :set_ticket
  before_action :set_issue, only: %i[show destroy edit update]
  load_and_authorize_resource

  def index
    @issues = @ticket.issues
  end

  def show; end

  def new
    @issue = @ticket.issues.new
  end

  def create
    @issue = @ticket.issues.new(issue_params)
    @issue.project = @project
    @issue.user = current_user
    @issue.message_type ||= 'external'
    audit_on_create(@issue)
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@issue)
      .event('issue.create')
      .with_properties(project_id: @project.id, ticket_id: @ticket.id, message_type: @issue.message_type)
      .log('Issue created')

    if @issue.content.blank?
      @issue.errors.add(:content, 'Message cannot be blank.')
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            'new_message_form',
            partial: 'issues/form',
            locals: { project: @project, ticket: @ticket, issue: @issue }
          )
        end
        format.html { render :new, status: :unprocessable_entity }
      end
      return
    end

    respond_to do |format|
      if @issue.save
        send_email_notifications(@issue, current_user)
        current_user.add_role :creator, @issue

        if @issue.message_type == 'external'
          # Notify only the current assignee and project owner by default
          assignee = @ticket.users.first || @project.user
          owner = @project.user
          recipients = [assignee, owner].compact.uniq

          recipients.each do |target|
            next if target.email.blank?

            Messaging::EmailSender
              .send_email(
                "New Message for Ticket ##{@ticket.unique_id}",
                to: [target.email],
                actor: Current.user,
                priority: :normal,
                type: 'issue_created'
              )
              .use_template(view: 'user_mailer/issue_created_email', assigns: { user: target, issue: @issue, project: @project, ticket: @ticket,
                                                                                current_user: Current.user })
              .set_source('ticket', @ticket.id)
              .set_party('user', Current.user&.id)
              .send(queue: true)
          end
        end

        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.prepend('messages-list', # Fixed target ID
                                 partial: 'issues/message',
                                 locals: { item: @issue }),
            turbo_stream.replace('new_message_form',
                                 partial: 'issues/form',
                                 locals: { project: @project, ticket: @ticket, issue: Issue.new }),
            turbo_stream.update('messageFormContainer',
                                html: '')
          ]
        end
        format.html { redirect_to project_ticket_path(@project, @ticket) }
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            'new_message_form',
            partial: 'issues/form',
            locals: { project: @project, ticket: @ticket, issue: @issue }
          )
        end
        format.html { render :new }
      end
    end
  end

  def edit
    respond_to do |format|
      format.turbo_stream
      format.html
    end
  end

  def update
    audit_on_update(@issue)
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@issue)
      .event('issue.update')
      .with_properties(project_id: @project.id, ticket_id: @ticket.id)
      .log('Issue updated')
    respond_to do |format|
      if @issue.update(issue_params)
        send_email_notifications(@issue, current_user)

        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              dom_id(@issue), # Replace just the updated message
              partial: 'issues/message',
              locals: { item: @issue }
            ),
            turbo_stream.remove("edit-form-#{@issue.id}") # Close the edit form
          ]
        end

        format.html { redirect_to project_ticket_path(@project, @ticket), notice: 'Issue was successfully updated.' }
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "edit-form-#{@issue.id}",
            partial: 'issues/edit_form',
            locals: { issue: @issue, project: @project, ticket: @ticket }
          )
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    if audit_soft_delete(@issue)
      # soft-deleted
    else
      @issue.destroy
    end
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@issue)
      .event('issue.destroy')
      .with_properties(project_id: @project.id, ticket_id: @ticket.id)
      .log('Issue removed')
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove(dom_id(@issue))
      end
      format.html { redirect_to project_ticket_path(@project, @ticket) }
    end
  end

  private

  def extract_mentioned_users(content)
    usernames = content.to_plain_text.scan(/@([\w\s]+)/).flatten # Convert to plain text
    User.where("CONCAT(first_name, ' ', last_name) IN (?)", usernames)
  end

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_ticket
    @ticket = @project.tickets.find(params[:ticket_id])
  end

  def set_issue
    @issue = @ticket.issues.find(params[:id])
  end

  def send_email_notifications(_issue, sender)
    selected_users = User.where(id: params.dig(:team, :user_ids)) # Safely fetch user IDs
    return if selected_users.blank?

    selected_users.each do |user|
      Messaging::EmailSender
        .send_email(
          "New Comment on Ticket ##{@ticket.unique_id}",
          to: [user.email],
          actor: sender,
          priority: :normal,
          type: 'mention_issue'
        )
        .use_template(view: 'user_mailer/mention_user_in_issue', assigns: { user:, issue: @issue, sender:, project: @project, ticket: @ticket })
        .set_source('ticket', @ticket.id)
        .set_party('user', sender.id)
        .send(queue: true)
    end
  end

  # Permit content and attachments to be handled in the params
  def issue_params
    params.require(:issue).permit(:content, :ticket_id, :project_id, :user_id, :message_type, attachments: [])
  end
end
