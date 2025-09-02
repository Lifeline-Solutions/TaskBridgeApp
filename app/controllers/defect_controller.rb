class DefectController < ApplicationController
  before_action :authenticate_user!
  before_action :set_defect, only: %i[show edit update update_priority destroy add_defect add_attachments remove_attachment update_label modal_show]

  def index
    @defects = Defect.published.includes(:users, :qa_module, :submodule, :banking_type, :statuses)
      .order(created_at: :desc)

    # Filter defects for non-admin users
    @defects = @defects.joins(:users).where(users: { id: current_user.id }) unless current_user.has_any_role?(:admin, :observer, :qa)

    # Status filter
    @defects = @defects.joins(:statuses).where(statuses: { id: params[:status] }) if params[:status].present?

    # Search filter

    if params[:query].present?
      @defects = @defects
        .left_joins(:users, product: %i[client groupwares])
        .where(
          'clients.name ILIKE :q
         OR groupwares.name ILIKE :q
         ',
          q: "%#{params[:query]}%"
        )
    end

    # Pagination
    @per_page = 20
    @page = (params[:page] || 1).to_i
    @total_pages = (@defects.count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, @defects.count].min
    @total_count = @defects.count
    @defects = @defects.offset((@page - 1) * @per_page).limit(@per_page)

    # ✅ Collect distinct statuses for dropdown (only from the currently matching defects)
    @statuses = Status.joins(:defects)
      .where(defects: { id: @defects.pluck(:id) })
      .distinct
      .order(:name)
  end

  def index_show
    # Base query for defects
    @defects = Defect.published.includes(:users, :qa_module, :submodule, :banking_type, :statuses)
      .order(created_at: :desc)

    # Filter by client name (coming from your link_to param)
    @defects = @defects.joins(product: :client).where(clients: { name: params[:client_name] }) if params[:client_name].present?

    # Restrict for non-admin users
    @defects = @defects.joins(:users).where(users: { id: current_user.id }) unless current_user.has_any_role?(:admin, :observer, :qa)

    # Status filter
    @defects = @defects.joins(:statuses).where(statuses: { id: params[:status] }) if params[:status].present?

    # Search filter
    if params[:query].present?
      @defects = @defects
        .left_joins(:users, product: %i[client groupwares])
        .where(
          'defects.summary ILIKE :q
         OR defects.defect_unique ILIKE :q
         OR defects.priority ILIKE :q
         OR users.first_name ILIKE :q
         OR users.last_name ILIKE :q
         OR clients.name ILIKE :q
         OR groupwares.name ILIKE :q
         OR CAST(defects.created_at AS TEXT) ILIKE :q',
          q: "%#{params[:query]}%"
        )
    end

    # Pagination
    @per_page = 20
    @page = (params[:page] || 1).to_i
    @total_count = @defects.count
    @total_pages = (@total_count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, @total_count].min
    @defects = @defects.offset((@page - 1) * @per_page).limit(@per_page)

    # Distinct statuses for dropdown
    @statuses = Status.joins(:defects).where(defects: { id: @defects.ids }).distinct.order(:name)

    # ✅ Render using the defects index or show-like template
    render :index_show
  end

  def show
    unless current_user.has_any_role?(:admin, :observer, :qa) || Defect.joins(:users).where(id: params[:id], users: { id: current_user.id }).exists?
      redirect_to defect_index_path, alert: 'You are not authorized to view this defect.' and return
    end

    @defect = Defect.find(params[:id])
    # Defects History
    @defects_history = DefectHistory.where(defect_id: @defect.id).order(created_at: :desc)

    # Attachment paginations
    @attachments_per_page = 6
    @attachments_page = (params[:attachments_page] || 1).to_i
    @attachments_total = @defect.attachments.count
    @attachments_total_pages = (@attachments_total / @attachments_per_page.to_f).ceil

    @attachments = @defect.attachments
      .offset((@attachments_page - 1) * @attachments_per_page)
      .limit(@attachments_per_page)
  end

  def modal_show
    render partial: 'defect/defect_show_modal', layout: false
  end

  def new
    @defect = Defect.new
    set_form_data
  end

  def create
    @defect = Defect.new(defect_params)
    @defect.creator = current_user
    selected_user_ids = params[:defect][:user_ids]

    # Explicitly set draft flag based on which button was clicked
    if params[:commit] == 'draft'
      @defect.draft = true
      @defect.label = 'Draft'
    else
      @defect.draft = false
    end

    if @defect.save
      @defect.user_ids = selected_user_ids

      if @defect.draft?
        redirect_to defect_index_path, notice: 'Draft defect saved successfully.'
      else
        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@defect)
          .event('defect.create')
          .with_properties(defect_attributes: @defect.attributes, assigned_user_ids: selected_user_ids)
          .log("Created Defect ##{@defect.id}, assigned to User IDs: #{selected_user_ids.join(', ')}")

        assigned_names = @defect.users.map { |u| "#{u.first_name} #{u.last_name}" }.join(', ')
        log_event(
          @defect, current_user, 'Created and Assigned',
          assigned_names.present? ? "Defect was created and assigned to #{assigned_names} at #{Time.now.strftime('%H:%M of  %d-%m-%Y')}" : "Defect was created but no assigned user at #{Time.now.strftime('%H:%M of  %d-%m-%Y')}"
        )

        redirect_to defect_index_path, notice: 'Defect was successfully created.'
      end
    else
      set_form_data
      flash.now[:alert] = "Defect creation failed: #{@defect.errors.full_messages.join(', ')}"
      render :new, status: :unprocessable_entity
    end
  end

  def modules_by_product
    product_id = params[:product_id]

    @modules = if product_id.present?
                 QaModule.where(product_id: product_id, parent_id: nil).order(:name)
               else
                 []
               end

    render json: @modules.select(:id, :name)
  end

  def edit
    @defect = Defect.find(params[:id])

    @qa_modules = QaModule.where(parent_id: nil)
    @banking_types = BankingType.all
    @products = Product.with_quality_assurance_status
    @users = User.with_agent_project_manager_role.order(:first_name, :last_name)
    @submodules = @defect.qa_module ? @defect.qa_module.submodules : []

    @statuses = Status.where(name: [
                               'To Do', 'In Progress', 'On hold', 'Awaiting client info',
                               'Awaiting build', 'QA testing', 'Closed', 'Failed QA',
                               'Blocked', 'Reopened'
                             ])

    # Dropdown options for product selection
    @products_and_clients_defects = Product.includes(:client, :groupwares, :statuses)
      .select do |product|
      product.statuses.any? do |status|
        status.name == 'Pre Quality Assurance' || status.name == 'End Of Quality Assurance'
      end
    end.map do |product|
      client_name = product.client&.name || 'No Client'
      groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
      ["#{client_name} - #{groupware_names}", product.id]
    end

    respond_to do |format|
      format.html
      format.turbo_stream { render layout: false }
    end
  end

  def update
    audit_on_update(@defect)

    selected_user_ids = params[:defect][:user_ids]

    if @defect.update(defect_params.except(:attachments))
      # Attach new files without removing old ones
      if params[:defect][:attachments].present?
        params[:defect][:attachments].each do |file|
          @defect.attachments.attach(file)
        end
      end

      @defect.user_ids = selected_user_ids

      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.update')
        .log("Updated Defect ##{@defect.id}")

      redirect_to @defect, notice: 'Defect was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if audit_soft_delete(@defect)
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.soft_delete')
        .log("Soft-deleted Defect ##{@defect.id}")
      redirect_to defect_url, notice: 'Defect was successfully deleted.'
    else
      @defect.destroy
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.destroy')
        .log("Destroyed Defect ##{@defect.id}")
      redirect_to defect_url, notice: 'Defect was successfully destroyed.'
    end
  end

  # add a user to the defect
  def add_defect
    if @defect.users.include?(User.find(params[:user_id]))
      redirect_to @defect, notice: 'User has already been assigned.'
    else
      user = User.find(params[:user_id])
      @defect.users.clear
      @defect.users << user
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.assign_user')
        .with_properties(user_id: user.id)
        .log("Assigned #{user.name} to Defect ##{@defect.id}")
      redirect_to defect_path(@defect), notice: "#{user.name}  was successfully assigned."

      log_event(
        @defect, current_user, 'Assigned to',
        user.present? ? "Defect was assigned to #{user.name} at #{Time.now.strftime('%H:%M of  %d-%m-%Y')}" : "Defect was Updated but no assigned user at #{Time.now.strftime('%H:%M of  %d-%m-%Y')}"
      )
    end
  end

  def drafts
    # @defects = current_user.defects.drafts
    @defects = Defect.drafts.includes(:users, :qa_module, :submodule).order(updated_at: :desc)

    # Pagination
    @per_page = 20
    @page = (params[:page] || 1).to_i
    @total_pages = (@defects.count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, @defects.count].min
    @total_count = @defects.count
    @defects = @defects.offset((@page - 1) * @per_page).limit(@per_page)

    # Collect distinct statuses for dropdown (only from the currently matching defects)
    @statuses = Status.joins(:defects)
      .where(defects: { id: @defects.pluck(:id) })
      .distinct
      .order(:name)

    render :index
  end

  def publish
    @defect = Defect.find(params[:id])
    if @defect.update(draft: false)
      redirect_to @defect, notice: 'Defect has been published successfully.'
    else
      redirect_to @defect, alert: 'Failed to publish defect.'
    end
  end

  def defect_status
    @defect = Defect.find(params[:id])
    status = Status.find(params[:status_id])
    @defect.statuses.clear
    @defect.statuses << status
    redirect_to defect_path(@defect), notice: 'Product status was successfully updated.'
    log_event(
      @defect, current_user, 'Status Changed',
      status.present? ? "Defect Status was changed to #{status.name} by #{current_user.name} at #{Time.now.strftime('%H:%M of  %d-%m-%Y')}" : "Defect was Updated but no assigned user at #{Time.now.strftime('%H:%M of  %d-%m-%Y')}"
    )
  end

  def remove_defect
    @defect = Defect.find(params[:id])
    user = User.find(params[:user_id])
    @defect.users.delete(user)
    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@defect)
      .event('defect.unassign_user')
      .with_properties(user_id: user.id)
      .log("Unassigned #{user.name} from Defect ##{@defect.id}")
    redirect_to defect_path(@defect), notice: "#{user.name} was successfully removed from the defect."
  end

  def get_submodules
    parent_module = QaModule.find(params[:module_id])
    @submodules = parent_module.submodules.active
    render json: @submodules
  end

  def add_attachments
    # Handle the file upload
    if params[:attachments].present?
      # params[:attachments] will be an array when using 'attachments[]' field name
      attachments = Array(params[:attachments]).reject(&:blank?)

      if attachments.any?
        attachments.each do |attachment|
          @defect.attachments.attach(attachment)
        end
        redirect_to defect_path(@defect), notice: "#{attachments.size} file(s) were successfully uploaded."
      else
        redirect_to defect_path(@defect), alert: 'No valid files selected.'
      end
    else
      redirect_to defect_path(@defect), alert: 'Please select at least one file to upload.'
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to defects_path, alert: 'Defect not found.'
  end

  def remove_attachment
    attachment = @defect.attachments.find(params[:attachment_id])
    attachment.purge
    redirect_to defect_path(@defect), notice: 'File was successfully removed.'
  rescue ActiveRecord::RecordNotFound
    redirect_to defects_path, alert: 'File or defect not found.'
  end

  def update_priority
    if @defect.update(priority: params[:defect][:priority])
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.update_priority')
        .with_properties(priority: @defect.priority)
        .log("Updated priority to #{@defect.priority} for Defect ##{@defect.id}")

      # Add history log
      log_event(
        @defect,
        current_user,
        'Priority Updated',
        "Priority was updated to #{@defect.priority} by #{current_user.name} at #{Time.now.strftime('%H:%M of %d-%m-%Y')}"
      )

      respond_to do |format|
        format.js
        format.html { redirect_to @defect, notice: 'Priority updated successfully.' }
      end
    else
      respond_to do |format|
        format.js
        format.html { render :show, alert: 'Failed to update priority.' }
      end
    end
  end

  def update_label
    if @defect.update(label: params[:defect][:label])
      # Activity log
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.update_label')
        .with_properties(label: @defect.label)
        .log("Updated label to #{@defect.label} for Defect ##{@defect.id}")

      # History log
      log_event(
        @defect,
        current_user,
        'Label Updated',
        "Label was updated to #{@defect.label} by #{current_user.name} at #{Time.now.strftime('%H:%M of %d-%m-%Y')}"
      )

      respond_to do |format|
        format.js
        format.html { redirect_to @defect, notice: 'Label updated successfully.' }
      end
    else
      respond_to do |format|
        format.js
        format.html { render :show, alert: 'Failed to update label.' }
      end
    end
  end

  private

  def set_form_data
    @qa_modules = QaModule.where(parent_id: nil)
    @banking_types = BankingType.all
    @users = User.with_agent_project_manager_role.order(:first_name, :last_name)
    @submodules = []
    # Fallback: If no QA product found, just pick first product
    @product ||= Product.includes(:client, :groupwares).first

    # Dropdown options for product selection
    @products_and_clients_defects = Product.includes(:client, :groupwares, :statuses)
      .select do |product|
      product.statuses.any? do |status|
        ['Pre Quality Assurance', 'End Of Quality Assurance'].include?(status.name)
      end
    end.map do |product|
      client_name = product.client&.name || 'No Client'
      groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
      ["#{client_name} - #{groupware_names}", product.id]
    end

    # Get all available statuses for the workflow
    @statuses = Status.where(name: [
                               'To Do', 'In Progress', 'On hold', 'Awaiting client info',
                               'Awaiting build', 'QA testing', 'Closed', 'Failed QA',
                               'Blocked', 'Reopened'
                             ])
  end

  def set_defect
    defect_id = params[:defect_id] || params[:id]
    @defect = Defect.find(defect_id)
  end

  def defect_params
    # Handle the qa_submodule_id to submodule_id mapping
    params[:defect][:submodule_id] = params[:defect].delete(:qa_submodule_id) if params[:defect] && params[:defect][:qa_submodule_id].present?

    # Convert user_ids from string to array if needed
    params[:defect][:user_ids] = [params[:defect][:user_ids]].reject(&:blank?) if params[:defect] && params[:defect][:user_ids].is_a?(String)

    params.require(:defect).permit(
      :summary,
      :content,
      :qa_module_id,
      :submodule_id,
      :banking_type_id,
      :priority,
      :label,
      :draft,
      :product_id,
      :issue_type,
      :defect_unique,
      user_ids: [],
      attachments: []
    )
  end

  def log_event(defect, user, history_type, history)
    DefectHistory.create(defect: defect, user: user, history_type: history_type, history: history)
  end
end
