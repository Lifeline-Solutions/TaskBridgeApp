class DefectController < ApplicationController
  before_action :authenticate_user!
  before_action :set_defect,
                only: %i[show edit update update_priority destroy add_defect add_attachments remove_attachment update_label modal_show add_label remove_label defect_status
                         create_failure_report search_for_linking link_defect unlink_defect]

  def index
    # Load defects with needed associations
    raw_defects = Defect.published.includes(:users, :qa_module, :submodule, :banking_type, :statuses, product: %i[client groupwares])
      .order(created_at: :desc)

    # Filter defects for non-admin users
    raw_defects = raw_defects.joins(:users).where(users: { id: current_user.id }) unless current_user.has_any_role?(:admin, :observer, :qa)

    # Status filter
    raw_defects = raw_defects.joins(:statuses).where(statuses: { id: params[:status] }) if params[:status].present?

    # Search filter
    if params[:query].present?
      raw_defects = raw_defects.left_joins(:users, product: %i[client groupwares]).where(
        'clients.name ILIKE :q OR groupwares.name ILIKE :q',
        q: "%#{params[:query]}%"
      )
    end

    # Group by client and first groupware name
    grouped = raw_defects.group_by do |defect|
      client_name = defect.product&.client&.name
      groupware_name = defect.product&.groupwares&.first&.name
      "#{client_name} #{groupware_name}"
    end

    # Paginate the groups instead of the defects.
    @per_page = 20
    @page = (params[:page] || 1).to_i

    group_keys = grouped.keys.sort # Optional: sort for stable pagination
    @total_pages = (group_keys.size / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, group_keys.size].min
    @total_count = group_keys.size

    # Only keep the groups for the current page
    paged_group_keys = group_keys[((@page - 1) * @per_page)...(((@page - 1) * @per_page) + @per_page)]
    @defect_groups = paged_group_keys.to_h { |k| [k, grouped[k]] }

    # Collect distinct statuses for dropdown (from currently matching defects)
    @statuses = Status.joins(:defects)
      .where(defects: { id: raw_defects.pluck(:id) })
      .distinct
      .order(:name)
  end

  #     @statuses = Status.joins(:defects).where(defects: { id: @defects.ids }).distinct.order(:name)
  def index_show
    # Base scope
    @defects = Defect.published
      .includes(:users, :qa_module, :labels, :banking_type, :statuses, product: %i[client groupwares])

    # Client filter (exact, case-insensitive)
    if params[:client_name].present?
      @defects = @defects.joins(product: :client)
        .where('LOWER(clients.name) = ?', params[:client_name].to_s.downcase.strip)
    end

    # Status filter (multiple checkboxes -> status[])
    selected_statuses = Array(params[:status]).reject(&:blank?)
    if selected_statuses.any?
      downcased = selected_statuses.map { |s| s.to_s.downcase }
      @defects = @defects.joins(:statuses)
        .where('LOWER(statuses.name) IN (?)', downcased)
    end

    # Labels filter (multiple check_boxes -> labels_ids[])
    selected_labels = Array(params[:label_ids]).reject(&:blank?)
    @defects = @defects.joins(:labels).where(labels: { id: selected_labels }) if selected_labels.any?

    # Priority filter (exact, case-insensitive)
    @defects = @defects.where('LOWER(defects.priority) = ?', params[:priority].to_s.downcase) if params[:priority].present?

    # Assignee filter
    @defects = @defects.joins(:users).where(users: { id: params[:user_id] }) if params[:user_id].present?

    # NEW: Module/Submodule/BankingType filters (by id)
    @defects = @defects.where(qa_module_id: params[:qa_module_id]) if params[:qa_module_id].present?
    @defects = @defects.where(qa_module_id: params[:submodule_id]) if params[:submodule_id].present?
    @defects = @defects.where(banking_type_id: params[:banking_type_id]) if params[:banking_type_id].present?
    @statuses = Status.joins(:defects).where(defects: { id: @defects.ids }).distinct.order(:name)

    # Date range filters
    start_date = params[:start_date].presence
    end_date = params[:end_date].presence
    begin
      if start_date.present? && end_date.present?
        from = Date.parse(start_date).beginning_of_day
        to = Date.parse(end_date).end_of_day
        @defects = @defects.where(defects: { created_at: from..to })
      elsif start_date.present?
        from = Date.parse(start_date).beginning_of_day
        @defects = @defects.where('defects.created_at >= ?', from)
      elsif end_date.present?
        to = Date.parse(end_date).end_of_day
        @defects = @defects.where('defects.created_at <= ?', to)
      end
    rescue ArgumentError
      # Ignore invalid dates without breaking the page
    end

    # Full-text search across related tables (now includes qa_modules, submodules, banking_types)
    if params[:query].present?
      q = "%#{params[:query].to_s.strip}%"
      @defects = @defects.left_joins(:users, :qa_module, :banking_type, product: %i[client groupwares]).where(
        "defects.summary ILIKE :q
         OR defects.defect_unique ILIKE :q
         OR defects.priority ILIKE :q
         OR users.first_name ILIKE :q
         OR users.last_name ILIKE :q
         OR clients.name ILIKE :q
         OR groupwares.name ILIKE :q
         OR qa_modules.name ILIKE :q
         OR banking_types.name ILIKE :q",
        q: q
      )
    end

    # Ordering
    @selected_order = params[:order]
    direction = %w[asc desc].include?(@selected_order) ? @selected_order : 'desc'
    @defects = @defects.order(created_at: direction)

    # Ensure uniqueness after joins (affects count and pagination)
    @defects = @defects.distinct

    # Build option lists for dropdowns from the CURRENT filtered (but unpaginated) result set
    filtered_ids = @defects.except(:select, :order, :limit, :offset).select(:id)
    @statuses = Status.joins(:defects)
      .where(defects: { id: filtered_ids })
      .distinct
      .order(:name)

    # NEW: option lists for QA Module, Submodule, Banking Type
    @qa_modules = QaModule.joins(:defects)
      .where(defects: { id: filtered_ids })
      .distinct
      .order(:name)

    @submodules = QaModule.joins(:defects)
      .where(defects: { id: filtered_ids })
      .where.not(parent_id: nil)
      .distinct
      .order(:name)

    @banking_types = BankingType.joins(:defects)
      .where(defects: { id: filtered_ids })
      .distinct
      .order(:name)

    @labels = Label.joins(:defects)
      .where(defects: { id: filtered_ids })
      .distinct
      .order(:name)

    # Pagination
    @per_page = 20
    @page = (params[:page] || 1).to_i
    @total_count = @defects.count
    @total_pages = (@total_count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, @total_count].min
    @defects = @defects.offset((@page - 1) * @per_page).limit(@per_page)

    render :index_show
  end

  def show
    unless current_user.has_any_role?(:admin, :observer, :qa) || Defect.joins(:users).where(id: params[:id], users: { id: current_user.id }).exists?
      redirect_to defect_index_path, alert: 'You are not authorized to view this defect.' and return
    end

    @defect = Defect.find(params[:id])
    # Defects History
    @defects_history = DefectHistory.where(defect_id: @defect.id).order(created_at: :desc)

    @timeline_items = @defect.timeline_items(order: :desc)

    # Attachment paginations
    @attachments_per_page = 6
    @attachments_page = (params[:attachments_page] || 1).to_i
    all_attachments = @defect.all_attachments
    @attachments_total = all_attachments.size
    @attachments_total_pages = (@attachments_total / @attachments_per_page.to_f).ceil

    @attachments = all_attachments.slice(
      (@attachments_page - 1) * @attachments_per_page,
      @attachments_per_page
    ) || []
  end

  def modal_show
    render partial: 'defect/defect_show_modal', layout: false
  end

  def new
    @defect = Defect.new

    default_assignee = DefaultDefectAssignee.where(archive_status: false).order(created_at: :desc).first
    @defect.user_ids = [default_assignee.user_id] if default_assignee&.user_id.present?

    set_form_data

    return unless @defect.product_id.present?

    @users = Product.find(@defect.product_id).users
  end

  def create
    @defect = Defect.new(defect_params)
    @defect.creator = current_user

    # Clean user_ids coming from hidden field (will be [""] if none selected)
    selected_user_ids = Array(params[:defect][:user_ids]).reject(&:blank?)

    # Fallback to global default assignee if no one selected
    if selected_user_ids.blank?
      default_assignee = DefaultDefectAssignee.where(archive_status: false)
        .order(created_at: :desc)
        .first
      selected_user_ids = [default_assignee.user_id.to_s] if default_assignee&.user_id.present?
    end

    # Assign before saving
    @defect.user_ids = selected_user_ids

    # Explicitly set draft flag
    @defect.draft = params[:commit] == 'draft'

    if @defect.save
      if @defect.draft?
        redirect_to @defect, notice: 'Draft defect saved successfully.'
      else
        activity('user_activity')
          .caused_by(current_user)
          .performed_on(@defect)
          .event('defect.create')
          .with_properties(defect_attributes: @defect.attributes,
                           assigned_user_ids: selected_user_ids)
          .log("Created Defect ##{@defect.id}, assigned to User IDs: #{selected_user_ids.join(', ')}")

        ProcessMentionsJob.perform_later(
          @defect.content&.body&.to_html,
          @defect.id,
          current_user.id,
          'defect_content'
        )

        assigned_names = @defect.users.map { |u| "#{u.first_name} #{u.last_name}" }.join(', ')
        log_event(
          @defect, current_user, 'Created and Assigned',
          assigned_names.present? ? "Defect was created and assigned to #{assigned_names} at #{Time.now.strftime('%H:%M of  %d-%m-%Y')}" : "Defect was created but no assigned user at #{Time.now.strftime('%H:%M of  %d-%m-%Y')}"
        )

        redirect_to @defect, notice: 'Defect was successfully created.'
        # Send An email to the creator and the assignee
        # app/controllers/defects_controller.rb
        UserMailer.new_defect_email(@defect, @defect.users.pluck(:email), current_user).deliver_later
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
    @banking_types = BankingType.all
    @products = Product.with_quality_assurance_status

    @users = @defect.craftsilicon_users.where.not(id: @defect.users.pluck(:id))
    @users = @users.where(id: @defect.product.users.pluck(:id)) if @defect.product.present?
    @users = @users.distinct.order(:first_name, :last_name)

    @statuses = Status.where(name: [
                               'To Do', 'In Progress', 'On hold', 'Awaiting client info',
                               'Awaiting build', 'QA testing', 'Closed', 'Failed QA',
                               'Blocked', 'Reopened'
                             ])

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

    @qa_modules = if @defect.product_id.present?
                    QaModule.where(product_id: @defect.product_id)
                  else
                    QaModule.all
                  end

    @submodules = if @defect.qa_module
                    # Select only id + name and make the result distinct (and ordered)
                    @defect.qa_module.submodules.select(:id, :name).distinct.order(:name)
                  else
                    QaModule.none
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

      # Process mentions in updated defect content asynchronously
      ProcessMentionsJob.perform_later(
        @defect.content&.body&.to_html,
        @defect.id,
        current_user.id,
        'defect_content'
      )

      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.update')
        .log("Updated Defect ##{@defect.id}")

      redirect_to @defect, notice: 'Defect was successfully updated.'
      UserMailer.edit_defect_email(@defect, @defect.users.pluck(:email), current_user).deliver_later

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
      UserMailer.defect_deleted_email(@defect, @defect.users.pluck(:email), current_user).deliver_later
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

  def add_label
    label_name = params[:label_name].strip
    label = Label.find_or_create_by(name: label_name.downcase)

    @defect.labels << label unless @defect.labels.include?(label)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @defect, notice: 'Label added successfully.' }
    end
  end

  def remove_label
    label = @defect.labels.find(params[:label_id])
    @defect.labels.destroy(label)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @defect, notice: 'Label removed successfully.' }
    end
  end

  def drafts
    @defects = Defect.drafts.includes(:users, :qa_module, :submodule).order(updated_at: :desc)

    # Pagination
    @per_page = 20
    @page = (params[:page] || 1).to_i
    @total_count = @defects.count
    @total_pages = (@total_count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, @total_count].min
    @defects = @defects.offset((@page - 1) * @per_page).limit(@per_page)

    # Collect distinct statuses for dropdown (only from the current page set)
    @statuses = Status.joins(:defects)
      .where(defects: { id: @defects.pluck(:id) })
      .distinct
      .order(:name)

    # Add the option lists for consistency with index_show
    filtered_ids = @defects.pluck(:id)

    @qa_modules = QaModule.where(id: Defect.where(id: filtered_ids).select(:qa_module_id)).distinct.order(:name)

    @submodules = QaModule.where(id: Defect.where(id: filtered_ids).select(:submodule_id))
      .where.not(parent_id: nil)
      .distinct
      .order(:name)

    @banking_types = BankingType.where(id: Defect.where(id: filtered_ids).select(:banking_type_id))
      .distinct
      .order(:name)

    render :index_show
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
    # Check if defect is blocked by another defect
    if @defect.blocked?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            'modal',
            partial: 'defect/blocked_status_modal',
            locals: { defect: @defect }
          )
        end
        format.html do
          redirect_to defect_path(@defect), alert: "Cannot change status: This defect is blocked by #{@defect.blocking_defect_names}. Please unlink blocking defects first."
        end
        format.json { render json: { success: false, message: "Cannot change status: This defect is blocked by #{@defect.blocking_defect_names}" } }
      end
      return
    end

    status = Status.find(params[:status_id])

    if status.name.strip.downcase == 'failed qa'
      # DO NOT persist the status yet; we need a reason
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            'modal',
            partial: 'defect/failure_reason_modal',
            locals: { defect: @defect }
          )
        end
        format.html { redirect_to defect_path(@defect), alert: 'Failed QA requires a reason.' }
      end
      return
    end

    # Non-Failed QA: commit the status change now
    @defect.transaction do
      @defect.statuses.clear
      @defect.statuses << status
    end

    log_event(
      @defect, current_user, 'Status Changed',
      "Defect Status was changed to #{status.name} by #{current_user.name} at #{Time.now.strftime('%H:%M of %d-%m-%Y')}"
    )

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace('modal', partial: 'defect/modal_empty'),
          turbo_stream.replace("defect_status_#{@defect.id}", partial: 'defect/status_badge', locals: { defect: @defect })
        ]
      end
      format.html { redirect_to defect_path(@defect), notice: 'Defect status was successfully updated.' }
    end
  end

  # POST /defect/:id/create_failure_report
  def create_failure_report
    authorize_view_failure_reports!

    reason_html = params.dig(:defect_failure_report, :reason)

    begin
      DefectRecordFailureService.new(defect: @defect, actor: current_user, reason_html: reason_html).call

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace('modal', partial: 'defect/modal_empty'),
            turbo_stream.replace("defect_status_#{@defect.id}", partial: 'defect/status_badge', locals: { defect: @defect })
          ]
        end

        format.html { redirect_to defect_path(@defect), notice: 'Failure reason recorded successfully.' }
      end
    rescue ActiveRecord::RecordInvalid => e
      @failure_report = e.record
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            'modal',
            partial: 'defect/failure_reason_modal',
            locals: { defect: @defect, failure_report: @failure_report }
          ), status: :unprocessable_entity
        end
        format.html do
          flash.now[:alert] = "Could not save failure reason: #{@failure_report.errors.full_messages.join(', ')}"
          render :show, status: :unprocessable_entity
        end
      end
    end
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

  # Defect linking actions
  def search_for_linking
    return unless params[:query].present?

    # Search for defects excluding the current one
    @defects = Defect.published
      .where.not(id: params[:id])
      .where('defect_unique ILIKE ? OR summary ILIKE ?',
             "%#{params[:query]}%", "%#{params[:query]}%")
      .includes(:product, :creator)
      .limit(20)

    render json: @defects.map { |defect|
      {
        id: defect.id,
        defect_unique: defect.defect_unique,
        summary: defect.summary,
        product_name: defect.product&.name,
        creator_name: defect.creator&.full_name || defect.creator&.email
      }
    }
  end

  def link_defect
    target_defect = Defect.find(params[:target_defect_id])

    if @defect.link_as_blocked_by(target_defect)
      render json: {
        success: true,
        message: "Successfully linked #{@defect.defect_unique} as blocked by #{target_defect.defect_unique}",
        target_defect: {
          id: target_defect.id,
          defect_unique: target_defect.defect_unique,
          title: target_defect.title,
          status: target_defect.statuses.first&.name
        }
      }
    else
      render json: {
        success: false,
        message: 'Failed to link defects. They may already be linked or there was an error.'
      }
    end
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, message: 'Defect not found.' }
  end

  def unlink_defect
    target_defect = Defect.find(params[:target_defect_id])

    if @defect.unlink_from(target_defect)
      render json: {
        success: true,
        message: "Successfully unlinked #{@defect.defect_unique} from #{target_defect.defect_unique}"
      }
    else
      render json: {
        success: false,
        message: 'Failed to unlink defects.'
      }
    end
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, message: 'Defect not found.' }
  end

  private

  def authorize_view_failure_reports!
    return if current_user.has_role?(:qa) || current_user.has_role?(:hod) || current_user.has_role?(:admin)

    redirect_to defect_path(@defect), notice: 'You are not authorized to view failure reports.'
  end

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
                               'TO DO', 'In Progress', 'On-Hold', 'Awaiting Client Info', 'Awaiting Build',
                               'QA Testing', 'Closed', 'Failed QA', 'Blocked', 'Reopened'
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
      :draft,
      :product_id,
      :issue_type,
      :retest_count,
      :defect_unique,
      user_ids: [],
      label_ids: [],
      status_ids: [],
      attachments: []
    )
  end

  def log_event(defect, user, history_type, history)
    DefectHistory.create(defect: defect, user: user, history_type: history_type, history: history)
  end
end
