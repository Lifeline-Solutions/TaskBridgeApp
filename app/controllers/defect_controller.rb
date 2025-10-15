class DefectController < ApplicationController
  before_action :authenticate_user!
  before_action :set_defect,
                only: %i[show edit update update_priority destroy add_defect add_attachments remove_attachment update_label modal_show add_label remove_label defect_status
                         create_failure_report search_for_linking link_defect unlink_defect]

  def index
    # Get products that are in QA status (product-level statuses)
    qa_status_names = ['Pre Quality Assurance', 'End Of Quality Assurance']

    @qa_products = Product
      .includes(:client, :groupwares, :statuses)
      .joins(:statuses)
      .where(statuses: { name: qa_status_names })
      .where('products.deleted_on IS NULL')
      .distinct
      .order('products.document_name ASC')

    # Apply search filter to QA products if query present
    if params[:query].present?
      @qa_products = @qa_products.left_joins(:client, :groupwares).where(
        'clients.name ILIKE :q OR groupwares.name ILIKE :q OR products.document_name ILIKE :q',
        q: "%#{params[:query]}%"
      )
    end

    # Get defects for these QA products (for counting and display)
    qa_product_ids = @qa_products.map(&:id)

    if qa_product_ids.any?
      # Base defects query for QA products - NO ORDERING YET
      raw_defects = Defect.published
        .includes(:users, :qa_module, :submodule, :banking_type, :statuses, product: %i[client groupwares])
        .where(product_id: qa_product_ids)

      # Filter defects for non-admin users
      raw_defects = raw_defects.joins(:users).where(users: { id: current_user.id }) unless current_user.has_any_role?(:admin, :observer, :qa)

      # Apply additional filters (this adds ordering)
      raw_defects = apply_defect_filters(raw_defects)

      # Status filter (defect status)
      raw_defects = raw_defects.joins(:statuses).where(statuses: { id: params[:status] }) if params[:status].present?

      # Get defect counts FIRST - before any grouping/ordering issues
      @qa_product_defect_counts = raw_defects.except(:order).group(:product_id).count

      # For grouping defects by product, remove ordering to avoid PG grouping error
      defects_for_grouping = raw_defects.except(:order)
      @defects_by_product = defects_for_grouping.group_by(&:product_id)

      # For status dropdown - collect statuses from the defects we're showing
      @statuses = Status.joins(:defects)
        .where(defects: { id: raw_defects.except(:order).pluck(:id) })
        .distinct
        .order(:name)
    else
      @defects_by_product = {}
      @qa_product_defect_counts = {}
      @statuses = Status.none
    end

    # NEW: Get filter options based on selected product (MIRRORING index_show)
    @selected_product_id = params[:product_id]
    @selected_module_id = params[:qa_module_id]

    # Create base scope for filter options
    if @selected_product_id.present?
      defects_scope = Defect.published.where(product_id: @selected_product_id)
    elsif qa_product_ids.any?
      defects_scope = Defect.published.where(product_id: qa_product_ids)
    end

    # Apply user filter for non-admin users
    defects_scope = defects_scope.joins(:users).where(users: { id: current_user.id }) if defects_scope && !current_user.has_any_role?(:admin, :observer, :qa)

    # Get filter options from defects scope
    if defects_scope
      # Remove ordering for filter options queries
      filtered_ids = defects_scope.except(:select, :order, :limit, :offset).select(:id)

      # Get modules (qa_modules with no parent_id)
      @qa_modules = QaModule.joins(:defects)
        .where(defects: { id: filtered_ids })
        .where(parent_id: nil) # Only modules, not submodules
        .distinct
        .order(:name)

      # Handle submodules based on selected module - FIXED VERSION
      @submodules = if @selected_module_id.present?
                      # Get ALL submodules for the selected module (not just those with defects)
                      # This ensures the dropdown shows all available submodules even if they don't have defects yet
                      QaModule.where(parent_id: @selected_module_id)
                        .order(:name)
                    else
                      # Show all submodules for the product (all qa_modules with parent_id not nil)
                      QaModule.joins(:defects)
                        .where(defects: { id: filtered_ids })
                        .where.not(parent_id: nil) # All submodules
                        .distinct
                        .order(:name)
                    end

      @banking_types = BankingType.joins(:defects)
        .where(defects: { id: filtered_ids })
        .distinct
        .order(:name)

      @labels = Label.joins(:defects)
        .where(defects: { id: filtered_ids })
        .distinct
        .order(:name)

      @assignees = User.joins(:defects)
        .where(defects: { id: filtered_ids })
        .distinct
        .order(:first_name, :last_name)
    else
      # Initialize empty arrays if no defects scope
      @qa_modules = []
      @submodules = []
      @banking_types = []
      @labels = []
      @assignees = []
    end

    # Track if filter should be open
    @filter_open = params[:filter_open].present?

    # Paginate the QA products instead of defect groups
    @per_page = 20
    @page = (params[:page] || 1).to_i
    @total_count = @qa_products.size
    @total_pages = (@total_count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, @total_count].min

    # Paginate the products
    @qa_products = @qa_products.offset((@page - 1) * @per_page).limit(@per_page)
  end

  def index_show
    # Base scope
    @defects = Defect.published
      .includes(:users, :qa_module, :labels, :banking_type, :statuses, product: %i[client groupwares])

    # Apply saved filter shortcut
    if params[:filter_id].present?
      filter = current_user.defect_filters.active.find_by(id: params[:filter_id])
      if filter
        merged = filter.sanitized_filters_string_keys || {}
        # Prefer saved product_id if not provided in URL
        merged['product_id'] = filter.product_id if filter.product_id.present? && !merged.key?('product_id')
        merged.except!('page')
        redirect_to index_show_defect_index_path(merged) and return
      end
    end

    # Client filter (exact, case-insensitive, and scoped by product_id)
    if params[:client_name].present? && params[:product_id].present?
      @defects = @defects.joins(product: :client)
        .where('LOWER(clients.name) = ?', params[:client_name].to_s.downcase.strip)
        .where(products: { id: params[:product_id] })
    elsif params[:client_name].present?
      @defects = @defects.joins(product: :client)
        .where('LOWER(clients.name) = ?', params[:client_name].to_s.downcase.strip)
    elsif params[:product_id].present?
      @defects = @defects.where(product_id: params[:product_id])
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

    # FIXED: Module/Submodule filtering logic with intelligent fallback
    if params[:qa_module_id].present? && params[:submodule_id].present?
      # Both parent module and submodule selected
      submodule_defects = @defects.where(qa_module_id: params[:submodule_id])

      # Check if there are any defects for the specific submodule
      if submodule_defects.exists?
        # Use the specific submodule filter
        @defects = submodule_defects
        @used_submodule_filter = true
      else
        # Fallback: Check if parent module has defects
        parent_module_defects = @defects.where(qa_module_id: params[:qa_module_id])
        if parent_module_defects.exists?
          # Use parent module defects since submodule has none
          @defects = parent_module_defects
          @used_parent_fallback = true
          @requested_submodule = QaModule.find_by(id: params[:submodule_id])
        else
          # Neither submodule nor parent module has defects
          @defects = submodule_defects
          @used_submodule_filter = true
        end
      end
    elsif params[:qa_module_id].present?
      # Only parent module selected - include all its submodules
      parent_module = QaModule.find_by(id: params[:qa_module_id])
      if parent_module
        submodule_ids = parent_module.children.pluck(:id)
        all_module_ids = [parent_module.id] + submodule_ids
        @defects = @defects.where(qa_module_id: all_module_ids)
      else
        @defects = @defects.where(qa_module_id: params[:qa_module_id])
      end
    elsif params[:submodule_id].present?
      # Only submodule selected without parent module
      @defects = @defects.where(qa_module_id: params[:submodule_id])
    end

    @defects = @defects.where(banking_type_id: params[:banking_type_id]) if params[:banking_type_id].present?

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

    @product = Product.find(params[:product_id]) if params[:product_id].present?

    # Build option lists for dropdowns from the CURRENT filtered (but unpaginated) result set
    filtered_ids = @defects.except(:select, :order, :limit, :offset).select(:id)
    @statuses = Status.joins(:defects)
      .where(defects: { id: filtered_ids })
      .distinct
      .order(:name)

    # NEW: option lists for QA Module, Submodule, Banking Type - UPDATED SUBMODULE LOGIC
    @qa_modules = QaModule.joins(:defects)
      .where(defects: { id: filtered_ids })
      .where(parent_id: nil) # Only parent modules
      .distinct
      .order(:name)

    # Handle submodules based on selected module
    @submodules = if params[:qa_module_id].present?
                    # Get ALL submodules for the selected module (not just those with defects)
                    QaModule.where(parent_id: params[:qa_module_id])
                      .order(:name)
                  else
                    # Show all submodules for the product (all qa_modules with parent_id not nil)
                    QaModule.joins(:defects)
                      .where(defects: { id: filtered_ids })
                      .where.not(parent_id: nil) # All submodules
                      .distinct
                      .order(:name)
                  end

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
    redirect_to defect_index_path, alert: 'You are not authorized to view this defect.' and return unless current_user.has_any_role?(:admin, :observer, :qa) || Defect.joins(:users).where(id: params[:id], users: { id: current_user.id }).exists?

    @defect = Defect.find(params[:id])

    qa_user_ids = User.joins(:roles)
      .where(roles: { name: 'qa' })
      .pluck(:id)

    product_user_ids = @defect.craftsilicon_users
      .where.not(id: @defect.users.pluck(:id))
      .where(id: @defect.product.users.pluck(:id))
      .pluck(:id)

    @available_users = User.where(id: qa_user_ids + product_user_ids)
      .distinct
      .order(:first_name, :last_name)

    # Defects History
    @defects_history = DefectHistory.where(defect_id: @defect.id).order(created_at: :desc)

    @timeline_items = @defect.timeline_items(order: :desc)

    # Attachment paginations
    @attachments_per_page = 6
    @attachments_page = (params[:attachments_page] || 1).to_i
    all_attachments = @defect.all_attachments.sort_by(&:created_at).reverse
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

    # Handle default assignee
    default_assignee = DefaultDefectAssignee.where(archive_status: false)
      .order(created_at: :desc)
      .first
    @defect.user_ids = [default_assignee.user_id] if default_assignee&.user_id.present?

    # Preselect product if product_id is passed
    if params[:product_id].present?
      @defect.product_id = params[:product_id]
      @selected_product = Product.find_by(id: params[:product_id])
    else
      @selected_product = nil
    end

    # Always run form setup after product selection
    set_form_data

    # Collect QA users
    qa_user_ids = User.joins(:roles)
      .where(roles: { name: 'qa' })
      .pluck(:id)

    # Collect product users (from selected product OR @product set by set_form_data)
    product = @selected_product || @product
    product_user_ids = product.present? ? product.users.pluck(:id) : []

    # Combine QA + Product users
    @available_users = User.where(id: qa_user_ids + product_user_ids)
      .distinct
      .order(:first_name, :last_name)

    # For JS (assignee search dropdown)
    @assignee_users_data = @available_users.map { |u| { id: u.id, name: u.name } }
  end

  def create
    @defect = Defect.new(defect_params)
    @defect.creator = current_user

    # Some forms submit product_id, qa_module_id and submodule_id at the top-level
    # instead of nested under defect[]. Ensure we copy them onto the model so
    # presence validations (Product, QA module) succeed.
    @defect.product_id ||= params[:product_id] if params[:product_id].present?
    @defect.qa_module_id ||= params[:qa_module_id] if params[:qa_module_id].present?
    @defect.submodule_id ||= params[:submodule_id] if params[:submodule_id].present?

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

    # QA users (get their IDs)
    qa_user_ids = User.joins(:roles)
      .where(roles: { name: 'qa' })
      .pluck(:id)

    # Product users (get their IDs)
    product_user_ids = @defect.craftsilicon_users
      .where.not(id: @defect.users.pluck(:id))
    product_user_ids = product_user_ids.where(id: @defect.product.users.pluck(:id)) if @defect.product.present?
    product_user_ids = product_user_ids.pluck(:id)

    # Combine and query
    @users = User.where(id: qa_user_ids + product_user_ids)
      .distinct
      .order(:first_name, :last_name)

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

      # Add an email to shot defect change
      UserMailer.add_user_defect_email(@defect, user.email, current_user).deliver_later

      log_event(
        @defect, current_user, 'Assigned to',
        user.present? ? "Defect was assigned to #{user.name} at #{Time.now.strftime('%H:%M of  %d-%m-%Y')}" : "Defect was Updated but no assigned user at #{Time.now.strftime('%H:%M of  %d-%m-%Y')}"
      )
    end
  end

  def drafts
    @defects = Defect.drafts.includes(:users, :qa_module, :submodule).order(updated_at: :desc)

    @labels = Label.all.order(:name)

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
          redirect_to defect_path(@defect),
                      alert: "Cannot change status: This defect is blocked by #{@defect.blocking_defect_names}. Please unlink blocking defects first."
        end
        format.json do
          render json: {
            success: false,
            message: "Cannot change status: This defect is blocked by #{@defect.blocking_defect_names}"
          }
        end
      end
      return
    end

    status = Status.find(params[:status_id])

    # Handle special case: Failed QA
    if status.name.strip.downcase == 'failed qa'
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

    # Proceed with normal status change
    @defect.transaction do
      @defect.statuses.clear
      @defect.statuses << status

      # Log event after successful status update
      log_event(
        @defect,
        current_user,
        'Status Changed',
        "Defect status was changed to #{status.name} by #{current_user.name} at #{Time.now.strftime('%H:%M on %d-%m-%Y')}"
      )
    end

    # Respond to the request
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace('modal', partial: 'defect/modal_empty'),
          turbo_stream.replace("defect_status_#{@defect.id}",
                               partial: 'defect/status_badge',
                               locals: { defect: @defect })
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
    if params[:module_id].present?
      parent_module = QaModule.find_by(id: params[:module_id])
      @submodules = if parent_module
                      # Use .children instead of .submodules if that's your association name
                      parent_module.children.order(:name)
                    else
                      []
                    end
    else
      @submodules = []
    end

    render json: @submodules.as_json(only: %i[id name])
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

  def defects_download
    require 'csv'
    defects = Defect.all

    # Search query (client or groupware)
    if params[:query].present?
      q = "%#{params[:query]}%"
      defects = defects.left_joins(product: %i[client groupwares])
        .where('clients.name ILIKE :q OR groupwares.name ILIKE :q', q: q)
    end

    defects = defects.where(banking_type_id: params[:banking_type_id]) if params[:banking_type_id].present?
    defects = defects.where('created_at >= ?', params[:start_date]) if params[:start_date].present?
    defects = defects.where('created_at <= ?', params[:end_date]) if params[:end_date].present?

    # Status filter (multi-select)
    if params[:status].present?
      statuses = Array(params[:status])
      defects = defects.joins(:statuses).where(statuses: { name: statuses })
    end

    # Priority filter
    defects = defects.where(priority: params[:priority]) if params[:priority].present?

    # Assignee filter
    defects = defects.joins(:users).where(users: { id: params[:user_id] }) if params[:user_id].present?

    # Module filter
    defects = defects.where(qa_module_id: params[:qa_module_id]) if params[:qa_module_id].present?

    # Submodule filter
    defects = defects.where(submodule_id: params[:submodule_id]) if params[:submodule_id].present?

    # Labels filter (multi-select)
    if params[:label_ids].present?
      label_ids = Array(params[:label_ids]).reject(&:blank?)
      defects = defects.joins(:labels).where(labels: { id: label_ids }).distinct if label_ids.any?
    end

    # Order (sort by created_at)
    defects = if params[:order].present? && %w[asc desc].include?(params[:order])
                defects.order(created_at: params[:order])
              else
                defects.order(created_at: :desc)
              end

    # Generate CSV
    csv_data = CSV.generate(headers: true) do |csv|
      csv << [
        'Defect ID', 'Status', 'Summary', 'Priority', 'Module', 'Sub Module',
        'Banking Types', 'Labels', 'Assignee', 'Reporter', 'Project',
        'Created At'
      ]
      defects.find_each do |defect|
        client_and_groupware = [defect.product.client&.name, defect.product.groupwares.first&.name].compact.join(' - ')
        csv << [
          defect.defect_unique,
          defect.statuses.map(&:name).join(', '),
          defect.summary,
          defect.priority,
          defect.qa_module&.name,
          defect.submodule&.name,
          defect.banking_type&.name,
          defect.labels.map(&:name).join(', '),
          defect.users.map { |u| "#{u.first_name} #{u.last_name}" }.join(', '),
          defect.creator&.name,
          client_and_groupware,
          defect.created_at.strftime('%Y-%m-%d %H:%M')
        ]
      end
    end

    send_data csv_data, filename: "defects_#{Time.zone.now.strftime('%Y-%m-%d %H:%M')}.csv", type: 'text/csv'
  end

  def defects_download_excel
    # Start with base scope matching index_show
    defects = Defect.published
      .includes(:users, :qa_module, :labels, :banking_type, :statuses, product: %i[client groupwares])

    # Apply the same filters as index_show
    # Client filter (exact, case-insensitive)
    if params[:client_name].present?
      defects = defects.joins(product: :client)
        .where('LOWER(clients.name) = ?', params[:client_name].to_s.downcase.strip)
    end

    # Product filter
    defects = defects.where(product_id: params[:product_id]) if params[:product_id].present?

    # Status filter (multiple checkboxes -> status[])
    selected_statuses = Array(params[:status]).reject(&:blank?)
    if selected_statuses.any?
      downcased = selected_statuses.map { |s| s.to_s.downcase }
      defects = defects.joins(:statuses)
        .where('LOWER(statuses.name) IN (?)', downcased)
    end

    # Labels filter (multiple checkboxes -> labels_ids[])
    selected_labels = Array(params[:label_ids]).reject(&:blank?)
    defects = defects.joins(:labels).where(labels: { id: selected_labels }) if selected_labels.any?

    # Priority filter (exact, case-insensitive)
    defects = defects.where('LOWER(defects.priority) = ?', params[:priority].to_s.downcase) if params[:priority].present?

    # Assignee filter
    defects = defects.joins(:users).where(users: { id: params[:user_id] }) if params[:user_id].present?

    # Module/Submodule/BankingType filters
    defects = defects.where(qa_module_id: params[:qa_module_id]) if params[:qa_module_id].present?
    defects = defects.where(submodule_id: params[:submodule_id]) if params[:submodule_id].present?
    defects = defects.where(banking_type_id: params[:banking_type_id]) if params[:banking_type_id].present?

    # Date range filters
    start_date = params[:start_date].presence
    end_date = params[:end_date].presence
    begin
      if start_date.present? && end_date.present?
        from = Date.parse(start_date).beginning_of_day
        to = Date.parse(end_date).end_of_day
        defects = defects.where(created_at: from..to)
      elsif start_date.present?
        from = Date.parse(start_date).beginning_of_day
        defects = defects.where('defects.created_at >= ?', from)
      elsif end_date.present?
        to = Date.parse(end_date).end_of_day
        defects = defects.where('defects.created_at <= ?', to)
      end
    rescue ArgumentError
      # Ignore invalid dates
    end

    # Full-text search
    if params[:query].present?
      q = "%#{params[:query].to_s.strip}%"
      defects = defects.left_joins(:users, :qa_module, :banking_type, product: %i[client groupwares]).where(
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
    direction = %w[asc desc].include?(params[:order]) ? params[:order] : 'desc'
    defects = defects.order(created_at: direction)

    # Ensure uniqueness after joins
    defects = defects.distinct

    # --- generate Excel using caxlsx ---
    package = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: 'Defects') do |sheet|
      sheet.add_row [
        'Defect ID', 'Status', 'Summary', 'Priority', 'Module', 'Sub Module',
        'Banking Types', 'Labels', 'Assignee', 'Reporter', 'Project', 'Created At'
      ]

      defects.find_each do |defect|
        client_and_groupware = [defect.product.client&.name, defect.product.groupwares.first&.name].compact.join(' - ')

        sheet.add_row [
          defect.defect_unique,
          defect.statuses.map(&:name).join(', '),
          defect.summary,
          defect.priority,
          defect.qa_module&.name,
          defect.submodule&.name,
          defect.banking_type&.name,
          defect.labels.map(&:name).join(', '),
          defect.users.map { |u| "#{u.first_name} #{u.last_name}" }.join(', '),
          defect.creator&.name,
          client_and_groupware,
          defect.created_at.strftime('%Y-%m-%d %H:%M')
        ]
      end
    end

    send_data package.to_stream.read,
              filename: "defects_#{Time.zone.now.strftime('%Y%m%d_%H%M%S')}.xlsx",
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  def link_defect
    target_defect = Defect.find(params[:target_defect_id])

    if @defect.link_as_blocked_by(target_defect)
      log_event(@defect, current_user, 'link_defect', "Linked as blocked by #{target_defect.defect_unique}")

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

  def add_attachments
    if params[:attachments].present?
      attachments = Array(params[:attachments]).reject(&:blank?)

      if attachments.any?
        attachments.each do |attachment|
          @defect.attachments.attach(attachment)
          log_event(@defect, current_user, 'add_attachment', "Added attachment #{attachment.original_filename}")
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
    filename = attachment.blob.filename.to_s
    attachment.purge

    log_event(@defect, current_user, 'remove_attachment', "Removed attachment #{filename}")

    redirect_to defect_path(@defect), notice: 'File was successfully removed.'
  rescue ActiveRecord::RecordNotFound
    redirect_to defects_path, alert: 'File or defect not found.'
  end

  def add_label
    label_name = params[:label_name].strip
    label = Label.find_or_create_by(name: label_name.downcase)

    unless @defect.labels.include?(label)
      @defect.labels << label
      log_event(@defect, current_user, 'add_label', "Added label #{label.name}")
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @defect, notice: 'Label added successfully.' }
    end
  end

  def remove_label
    label = @defect.labels.find(params[:label_id])
    @defect.labels.destroy(label)

    log_event(@defect, current_user, 'remove_label', "Removed label #{label.name}")

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @defect, notice: 'Label removed successfully.' }
    end
  end

  private

  def apply_defect_filters(defects_scope)
    # Priority filter
    defects_scope = defects_scope.where(priority: params[:priority]) if params[:priority].present?

    # Assignee filter
    defects_scope = defects_scope.joins(:users).where(users: { id: params[:user_id] }) if params[:user_id].present?

    # Banking type filter
    defects_scope = defects_scope.where(banking_type_id: params[:banking_type_id]) if params[:banking_type_id].present?

    # Date range filter
    if params[:start_date].present? && params[:end_date].present?
      start_date = Date.parse(params[:start_date])
      end_date = Date.parse(params[:end_date])
      defects_scope = defects_scope.where(created_at: start_date.beginning_of_day..end_date.end_of_day)
    end

    # QA Module and Submodule filter - THIS IS THE KEY FIX
    if params[:qa_module_id].present?
      if params[:submodule_id].present?
        # Filter by specific submodule
        defects_scope = defects_scope.where(qa_module_id: params[:submodule_id])
      else
        # Filter by parent module - include all its submodules
        parent_module = QaModule.find_by(id: params[:qa_module_id])
        if parent_module
          submodule_ids = parent_module.children.pluck(:id)
          all_module_ids = [parent_module.id] + submodule_ids
          defects_scope = defects_scope.where(qa_module_id: all_module_ids)
        else
          defects_scope = defects_scope.where(qa_module_id: params[:qa_module_id])
        end
      end
    end

    # Ordering
    order = params[:order] == 'asc' ? :asc : :desc
    defects_scope.order(created_at: order)
  end

  def authorize_view_failure_reports!
    return if current_user.has_role?(:qa) || current_user.has_role?(:hod) || current_user.has_role?(:admin)

    redirect_to defect_path(@defect), notice: 'You are not authorized to view failure reports.'
  end

  def set_form_data
    # selected product if provided in params (used to scope modules/banking types)
    @selected_product = (Product.find_by(id: params[:product_id]) if params[:product_id].present?)

    # QA modules (parent modules) - scoped to selected product if present
    @qa_modules = if @selected_product
                    QaModule.where(product_id: @selected_product.id, parent_id: nil).order(:name)
                  else
                    QaModule.where(parent_id: nil).order(:name)
                  end

    # banking types scoped to selected product (so UI can show only product banking types)
    @banking_types = if @selected_product
                       BankingType.where(product_id: @selected_product.id).order(:name)
                     else
                       []
                     end

    # If a module was selected (e.g. via params), preload its submodules for the view
    if params[:qa_module_id].present?
      @selected_module_id = params[:qa_module_id]
      parent_module = QaModule.find_by(id: params[:qa_module_id])
      @submodules = parent_module ? parent_module.submodules.order(:name) : []
    else
      @selected_module_id = nil
      @submodules = []
    end

    # also keep the currently selected submodule if any
    @selected_submodule_id = params[:submodule_id].presence

    # other existing dropdown data (unchanged)
    @users = User.with_agent_project_manager_role.order(:first_name, :last_name)
    @product ||= Product.includes(:client, :groupwares).first

    @products_and_clients_defects = Product.includes(:client, :groupwares, :statuses)
      .select do |product|
        product.statuses.any? { |status| ['Pre Quality Assurance', 'End Of Quality Assurance'].include?(status.name) }
      end.map do |product|
        client_name = product.client&.name || 'No Client'
        groupware_names = product.groupwares.any? ? product.groupwares.map(&:name).join(', ') : 'No Software'
        ["#{client_name} - #{groupware_names}", product.id]
      end

    # statuses ordering as you had it
    ordered_names = [
      'TO DO', 'Awaiting Build', 'Awaiting Client API', 'Awaiting Client Information',
      'Blocked', 'Failed QA', 'In Progress', 'On-Hold', 'QA Testing', 'Reopened',
      'Support Testing', 'Closed'
    ]
    found_statuses = Status.where(name: ordered_names)
    lookup = found_statuses.index_by(&:name)
    @statuses = ordered_names.map { |n| lookup[n] }.compact
  end

  def set_defect
    defect_id = params[:defect_id] || params[:id]
    @defect = Defect.find(defect_id)
  end

  def defect_params
    # Handle the qa_submodule_id to submodule_id mapping
    if params[:defect]
      params[:defect][:submodule_id] = params[:defect].delete(:qa_submodule_id) if params[:defect][:qa_submodule_id].present?

      # Normalize user_ids: could be a string, array or single value
      if params[:defect][:user_ids].is_a?(String)
        params[:defect][:user_ids] = [params[:defect][:user_ids]].reject(&:blank?)
      elsif params[:defect][:user_ids].is_a?(Array)
        params[:defect][:user_ids] = params[:defect][:user_ids].reject(&:blank?)
      end

      # Normalize incoming single status_id into status_ids array
      if params[:defect][:status_id].present?
        # If status_ids already present, merge; otherwise set
        existing = Array(params[:defect][:status_ids]).reject(&:blank?)
        params[:defect][:status_ids] = (existing + [params[:defect][:status_id]]).uniq
        params[:defect].delete(:status_id)
      end
    end

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
