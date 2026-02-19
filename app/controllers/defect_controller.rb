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

    # Get selected product IDs from params
    @selected_product_ids = Array(params[:product_id]).reject(&:blank?)

    # Determine if filters should be loaded
    @filters_loaded = @selected_product_ids.any? && params[:filter_open].present?

    # Use selected products or all QA products if none selected
    qa_product_ids = @selected_product_ids.any? ? @selected_product_ids : @qa_products.map(&:id)

    if qa_product_ids.any?
      # Base defects query for QA products - NO ORDERING YET
      # Use safe includes that won't break if columns don't exist
      raw_defects = Defect.published
        .includes(:users, :statuses, product: %i[client groupwares])
        .where(product_id: qa_product_ids)

      # Filter defects for non-admin users
      raw_defects = raw_defects.joins(:users).where(users: { id: current_user.id }) unless current_user.has_any_role?(:admin, :observer, :qa, :agent)

      # Apply additional filters (this adds ordering)
      raw_defects = apply_defect_filters(raw_defects)

      # Status filter (defect status) - handle array parameter
      raw_defects = raw_defects.joins(:statuses).where(statuses: { name: Array(params[:status]) }).distinct if params[:status].present?

      # Priority filter - handle array parameter
      raw_defects = raw_defects.where(priority: Array(params[:priority])) if params[:priority].present?

      # Assignee filter - handle array parameter
      raw_defects = raw_defects.joins(:users).where(users: { id: Array(params[:user_id]) }).distinct if params[:user_id].present?

      # Reporter filter - handle array parameter
      selected_reporters = Array(params[:reporter_id]).reject(&:blank?)
      raw_defects = raw_defects.where(created_by: selected_reporters) if selected_reporters.any?

      # Labels filter - handle array parameter
      raw_defects = raw_defects.joins(:labels).where(labels: { id: Array(params[:label_ids]) }).distinct if params[:label_ids].present?

      # Get defect counts FIRST - before any grouping/ordering issues
      @qa_product_defect_counts = raw_defects.except(:order, :distinct).distinct.group(:product_id).count

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

    # Get filter options based on selected products (only if filters are loaded)
    @selected_module_ids = Array(params[:qa_module_id]).reject(&:blank?)

    # Create base scope for filter options
    if @filters_loaded && @selected_product_ids.any?
      defects_scope = Defect.published.where(product_id: @selected_product_ids)
    elsif qa_product_ids.any?
      defects_scope = Defect.published.where(product_id: qa_product_ids)
    end

    # Apply user filter for non-admin users
    defects_scope = defects_scope.joins(:users).where(users: { id: current_user.id }) if defects_scope && !current_user.has_any_role?(:admin, :observer, :qa)

    # Initialize empty arrays for filter options
    @qa_modules = []
    @submodules = []
    @banking_types = []
    @labels = []
    @assignees = []

    # Only try to load filter options if we have defects AND the columns exist
    if defects_scope&.exists?
      # Remove ordering for filter options queries
      filtered_ids = defects_scope.except(:select, :order, :limit, :offset).select(:id)

      # Only load labels and assignees (safe associations)
      @labels = Label.joins(:defects)
        .where(defects: { id: filtered_ids })
        .distinct
        .order(:name)

      @assignees = User.joins(:defects)
        .where(defects: { id: filtered_ids })
        .distinct
        .order(:first_name, :last_name)

      # Try to load module/banking type options only if columns exist
      begin
        # Test if qa_module_id column exists by trying a simple query
        Defect.where(qa_module_id: nil).limit(1)

        # If we get here, the column exists - load the modules
        @qa_modules = if @selected_product_ids.any?
                        QaModule.where(product_id: @selected_product_ids, parent_id: nil)
                          .distinct
                          .order(:name)
                      else
                        QaModule.joins(:defects)
                          .where(defects: { id: filtered_ids })
                          .where(parent_id: nil)
                          .distinct
                          .order(:name)
                      end

        @submodules = if @selected_module_ids.any?
                        if @selected_product_ids.any?
                          QaModule.where(parent_id: @selected_module_ids, product_id: @selected_product_ids)
                            .order(:name)
                        else
                          QaModule.where(parent_id: @selected_module_ids)
                            .order(:name)
                        end
                      elsif @selected_product_ids.any?
                        QaModule.where(product_id: @selected_product_ids)
                          .where.not(parent_id: nil)
                          .distinct
                          .order(:name)
                      else
                        QaModule.joins(:defects)
                          .where(defects: { id: filtered_ids })
                          .where.not(parent_id: nil)
                          .distinct
                          .order(:name)
                      end
      rescue ActiveRecord::StatementInvalid
        # Columns don't exist yet, skip module options
        Rails.logger.warn 'QA module columns not available - skipping module filters'
      end

      begin
        # Test if banking_type_id column exists
        Defect.where(banking_type_id: nil).limit(1)

        # If we get here, the column exists - load banking types
        @banking_types = if @selected_product_ids.any?
                           BankingType.for_product(@selected_product_ids)
                             .distinct
                             .order(:name)
                         else
                           BankingType.joins(:defects)
                             .where(defects: { id: filtered_ids })
                             .distinct
                             .order(:name)
                         end
      rescue ActiveRecord::StatementInvalid
        # Column doesn't exist yet, skip banking types
        Rails.logger.warn 'Banking type column not available - skipping banking type filters'
      end
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
    # Determine if we need to skip eager loading due to GROUP BY sorting
    skip_eager_loading = params[:sort_by] == 'assignee'

    # Base scope - use safe includes that won't break if columns don't exist
    # Skip eager loading when using GROUP BY to avoid PostgreSQL grouping errors
    @defects = Defect.published

    unless skip_eager_loading
      @defects = @defects.includes(:users, :labels, :statuses, product: %i[client groupwares])

      # Safely add optional includes only if columns exist
      begin
        @defects = @defects.includes(:qa_module, :banking_type)
      rescue ActiveRecord::StatementInvalid
        # Columns don't exist yet, continue without these includes
        Rails.logger.warn 'Optional defect associations not available yet'
      end
    end

    # Apply saved filter shortcut
    if params[:filter_id].present?
      filter = current_user.defect_filters.active.find_by(id: params[:filter_id])
      if filter
        merged = filter.sanitized_filters_string_keys || {}
        # Prefer saved product_id if not provided in URL
        merged['product_id'] = filter.product_id if filter.product_id.present? && !merged.key?('product_id')
        merged.except!('page')
        redirect_to index_show_defect_index_path(merged.merge(current_filter_id: filter.id)) and return
      end
    end

    # Detect if current parameters match an existing saved filter (for update vs create logic)
    # Only consider actual filter parameters, not route parameters like client_name/product_id
    filter_only_params = {
      'status' => params[:status],
      'priority' => params[:priority],
      'user_id' => params[:user_id],
      'reporter_id' => params[:reporter_id],
      'qa_module_id' => params[:qa_module_id],
      'submodule_id' => params[:submodule_id],
      'banking_type_id' => params[:banking_type_id],
      'label_ids' => params[:label_ids],
      'query' => params[:query],
      'start_date' => params[:start_date],
      'end_date' => params[:end_date],
      'order' => params[:order]
    }.compact.reject { |_k, v| v.blank? || v == [] }

    # Only include product_id if there are other filters present (not just route navigation)
    filter_only_params['product_id'] = params[:product_id] if filter_only_params.any? && params[:product_id].present?

    @matching_filter = nil
    @current_filter = nil

    # If user applied a filter from dropdown, track it for potential updates
    @current_filter = current_user.defect_filters.active.find_by(id: params[:current_filter_id]) if params[:current_filter_id].present?
    @defects = @defects.joins(:users).where(users: { id: current_user.id }) unless current_user.has_any_role?(:admin, :observer, :qa, :agent)

    if filter_only_params.any? # Only look for matching filters if we have actual filter params
      @matching_filter = current_user.defect_filters.active.find do |filter|
        filter_params = filter.sanitized_filters_string_keys || {}
        filter_params['product_id'] = filter.product_id if filter.product_id.present?

        # Normalize both for comparison (convert arrays to sorted arrays for consistent comparison)
        normalized_current = normalize_filter_params(filter_only_params)
        normalized_saved = normalize_filter_params(filter_params)

        normalized_current == normalized_saved
      end
    end

    # Determine which filter to show for update: prefer current_filter if params changed, otherwise matching_filter
    @filter_to_update = @current_filter || @matching_filter

    # Handle multiple product_ids (array) or single product_id
    product_ids = Array(params[:product_id]).reject(&:blank?)

    # Client filter (exact, case-insensitive, and scoped by product_id)
    if params[:client_name].present? && product_ids.any?
      @defects = @defects.joins(product: :client)
        .where('LOWER(clients.name) = ?', params[:client_name].to_s.downcase.strip)
        .where(products: { id: product_ids })
    elsif params[:client_name].present?
      @defects = @defects.joins(product: :client)
        .where('LOWER(clients.name) = ?', params[:client_name].to_s.downcase.strip)
    elsif product_ids.any?
      @defects = @defects.where(product_id: product_ids)
    end

    # Status filter (multiple checkboxes -> status[])
    selected_statuses = Array(params[:status]).reject(&:blank?)
    if selected_statuses.any?
      downcased = selected_statuses.map { |s| s.to_s.downcase }
      @defects = @defects.joins(:statuses).where('LOWER(statuses.name) IN (?)', downcased)
      Rails.logger.info "After status filter: #{@defects.except(:distinct).distinct.count} defects"
    end

    # Priority filter (multiple checkboxes -> priority[]) - CASE INSENSITIVE
    selected_priorities = Array(params[:priority]).reject(&:blank?)
    if selected_priorities.any?
      # Build case-insensitive conditions for each priority
      priority_conditions = selected_priorities.map do |_priority|
        'LOWER(defects.priority) = LOWER(?)'
      end

      # Use OR conditions to match any of the selected priorities
      @defects = @defects.where(priority_conditions.join(' OR '), *selected_priorities)
      Rails.logger.info "After priority filter: #{@defects.except(:distinct).distinct.count} defects"
    end

    # Labels filter (multiple check_boxes -> labels_ids[])
    selected_labels = Array(params[:label_ids]).reject(&:blank?)
    if selected_labels.any?
      @defects = @defects.joins(:labels).where(labels: { id: selected_labels })
      Rails.logger.info "After labels filter: #{@defects.except(:distinct).distinct.count} defects"
    end

    # Assignee filter
    if params[:user_id].present?
      @defects = @defects.joins(:users).where(users: { id: params[:user_id] })
      Rails.logger.info "After assignee filter: #{@defects.except(:distinct).distinct.count} defects"
    end

    # Reporter filter (creator_id/created_by)
    selected_reporters = Array(params[:reporter_id]).reject(&:blank?)
    if selected_reporters.any?
      @defects = @defects.where(created_by: selected_reporters)
      Rails.logger.info "After reporter filter: #{@defects.except(:distinct).distinct.count} defects"
    end

    # Log count after all main filters
    Rails.logger.info "Defects after all main filters (before distinct): #{@defects.except(:distinct).distinct.count}"
    Rails.logger.info "SQL: #{@defects.to_sql}"

    # Module/Submodule filtering - only apply if columns exist
    begin
      qa_module_ids = Array(params[:qa_module_id]).reject(&:blank?)
      submodule_ids = Array(params[:submodule_id]).reject(&:blank?)

      if qa_module_ids.any? && submodule_ids.any?
        # Both parent modules and submodules selected
        submodule_defects = @defects.where(submodule_id: submodule_ids)

        # Check if there are any defects for the specific submodules
        if submodule_defects.exists?
          # Use the specific submodule filter
          @defects = submodule_defects
          @used_submodule_filter = true
        else
          # Fallback: Check if parent modules have defects
          parent_module_defects = @defects.where(qa_module_id: qa_module_ids)
          if parent_module_defects.exists?
            # Use parent module defects since submodules have none
            @defects = parent_module_defects
            @used_parent_fallback = true
            @requested_submodules = QaModule.where(id: submodule_ids)
          else
            # Neither submodules nor parent modules have defects
            @defects = submodule_defects
            @used_submodule_filter = true
          end
        end
      elsif qa_module_ids.any?
        # Only parent modules selected - include all their submodules
        parent_modules = QaModule.where(id: qa_module_ids)
        if parent_modules.any?
          submodule_ids = QaModule.where(parent_id: qa_module_ids).pluck(:id)
          all_module_ids = qa_module_ids + submodule_ids
          @defects = @defects.where(qa_module_id: all_module_ids)
        else
          @defects = @defects.where(qa_module_id: qa_module_ids)
        end
      elsif submodule_ids.any?
        # Only submodules selected without parent modules
        @defects = @defects.where(submodule_id: submodule_ids)
      end
    rescue ActiveRecord::StatementInvalid
      # Module filtering not available, skip it
      Rails.logger.warn 'Module filtering not available - skipping'
    end

    # Banking type filter - only apply if column exists
    begin
      banking_type_ids = Array(params[:banking_type_id]).reject(&:blank?)
      @defects = @defects.where(banking_type_id: banking_type_ids) if banking_type_ids.any?
    rescue ActiveRecord::StatementInvalid
      # Banking type filtering not available, skip it
      Rails.logger.warn 'Banking type filtering not available - skipping'
    end

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

    # Full-text search across related tables - safely handle optional associations
    if params[:query].present?
      q = "%#{params[:query].to_s.strip}%"
      search_conditions = [
        'defects.summary ILIKE :q',
        'defects.defect_unique ILIKE :q',
        'defects.priority ILIKE :q',
        'users.first_name ILIKE :q',
        'users.last_name ILIKE :q',
        'clients.name ILIKE :q',
        'groupwares.name ILIKE :q'
      ]

      # Safely add optional search conditions
      begin
        search_conditions << 'qa_modules.name ILIKE :q'
      rescue StandardError
        # Skip if qa_modules association not available
      end

      begin
        search_conditions << 'banking_types.name ILIKE :q'
      rescue StandardError
        # Skip if banking_types association not available
      end

      # Use left_joins explicitly for searchable associations
      @defects = @defects.left_joins(:users) unless @defects.to_sql.include?('JOIN "users"')

      # Always join product/client/groupwares as they are in the core search
      @defects = @defects.left_joins(product: %i[client groupwares])

      # Conditionally join qa_modules if we are searching it
      begin
        @defects = @defects.left_joins(:qa_module) if search_conditions.any? { |c| c.include?('qa_modules.name') }
      rescue StandardError
        # Ignore if association doesn't exist
      end

      # Conditionally join banking_types if we are searching it
      begin
        @defects = @defects.left_joins(:banking_type) if search_conditions.any? { |c| c.include?('banking_types.name') }
      rescue StandardError
        # Ignore if association doesn't exist
      end

      @defects = @defects.where(
        search_conditions.join(' OR '), q: q
      ).distinct
    end

    # Ordering
    @selected_order = params[:order]
    @sort_by = params[:sort_by]
    @sort_direction = %w[asc desc].include?(params[:sort_direction]) ? params[:sort_direction] : 'asc'
    direction = %w[asc desc].include?(@selected_order) ? @selected_order : 'desc'

    @defects = case @sort_by
               when 'assignee'
                 @defects
                   .left_joins(:users)
                   .select('defects.*', "MIN(COALESCE(users.first_name, '')) as assignee_name")
                   .group('defects.id')
                   .order(Arel.sql("assignee_name #{@sort_direction == 'desc' ? 'DESC' : 'ASC'}"))
               when 'reporter'
                 @defects
                   .joins('LEFT JOIN users AS reporter_users ON reporter_users.id = defects.created_by')
                   .select('defects.*', 'reporter_users.first_name as reporter_first', 'reporter_users.last_name as reporter_last')
                   .order(Arel.sql("reporter_first #{@sort_direction == 'desc' ? 'DESC' : 'ASC'}, reporter_last #{@sort_direction == 'desc' ? 'DESC' : 'ASC'}"))
                   .distinct
               else
                 @defects.order(created_at: direction).distinct
               end

    # FIX: Handle multiple products - don't set @product if multiple products are selected
    if product_ids.any?
      if product_ids.size == 1
        # Single product - set @product for backward compatibility
        @product = Product.find_by(id: product_ids.first)
        @products = nil
      else
        # Multiple products - set @products array and leave @product nil
        @products = Product.where(id: product_ids).order(:document_name)
        @product = nil # Ensure @product is nil to avoid errors in partial
      end
    else
      @product = nil
      @products = nil
    end

    # Build option lists for dropdowns from the UNFILTERED result set (after product/client filters only)
    # This ensures all available options are shown, even if not currently selected in other filters
    unfiltered_base = Defect.published
      .includes(:users, :labels, :statuses, product: %i[client groupwares])

    # Apply only product and client filters to the base scope
    if params[:client_name].present? && product_ids.any?
      unfiltered_base = unfiltered_base.joins(product: :client)
        .where('LOWER(clients.name) = ?', params[:client_name].to_s.downcase.strip)
        .where(products: { id: product_ids })
    elsif params[:client_name].present?
      unfiltered_base = unfiltered_base.joins(product: :client)
        .where('LOWER(clients.name) = ?', params[:client_name].to_s.downcase.strip)
    elsif product_ids.any?
      unfiltered_base = unfiltered_base.where(product_id: product_ids)
    end

    unfiltered_ids = unfiltered_base.except(:select, :order, :limit, :offset).select(:id)

    # FIX: Use subqueries to avoid DISTINCT + ORDER BY issues, using unfiltered defects
    @statuses = Status.where(id: Status.joins(:defects)
      .where(defects: { id: unfiltered_ids })
      .distinct
      .select(:id))
      .order(:name)

    # Scope QA modules directly to selected products for consistency
    @qa_modules = if product_ids.any?
                    QaModule.where(product_id: product_ids, parent_id: nil)
                      .distinct
                      .order(:name)
                  else
                    QaModule.where(id: QaModule.joins(:defects)
                      .where(defects: { id: unfiltered_ids })
                      .where(parent_id: nil)
                      .distinct
                      .select(:id))
                      .order(:name)
                  end

    # Handle submodules based on selected modules - FIXED LOGIC with product scoping
    @submodules = if qa_module_ids.any?
                    # Get ALL submodules for the selected modules (scoped to products)
                    if product_ids.any?
                      QaModule.where(parent_id: qa_module_ids, product_id: product_ids).order(:name)
                    else
                      QaModule.where(parent_id: qa_module_ids).order(:name)
                    end
                  elsif product_ids.any?
                    # Show submodules for selected products
                    QaModule.where(product_id: product_ids)
                      .where.not(parent_id: nil)
                      .distinct
                      .order(:name)
                  else
                    # Fallback to submodules from defects
                    available_module_ids = @qa_modules.pluck(:id)
                    submodule_ids_from_defects = QaModule.joins(:defects)
                      .where(defects: { id: unfiltered_ids })
                      .where.not(parent_id: nil)
                      .distinct
                      .pluck(:id)

                    submodule_ids_from_modules = if available_module_ids.any?
                                                   QaModule.where(parent_id: available_module_ids).pluck(:id)
                                                 else
                                                   []
                                                 end

                    all_submodule_ids = (submodule_ids_from_defects + submodule_ids_from_modules).uniq
                    QaModule.where(id: all_submodule_ids).order(:name)
                  end

    # Scope banking types directly to selected products for consistency
    @banking_types = if product_ids.any?
                       BankingType.for_product(product_ids)
                         .distinct
                         .order(:name)
                     else
                       BankingType.where(id: BankingType.joins(:defects)
                         .where(defects: { id: unfiltered_ids })
                         .distinct
                         .select(:id))
                         .order(:name)
                     end

    @labels = Label.where(id: Label.joins(:defects)
      .where(defects: { id: unfiltered_ids })
      .distinct
      .select(:id))
      .order(:name)

    # Load assignees from unfiltered defects so all available assignees show in dropdown
    @assignees_for_filter = User.joins(:defects)
      .where(defects: { id: unfiltered_ids })
      .distinct
      .order(:first_name, :last_name)

    # Load reporters from unfiltered defects so all available reporters show in dropdown
    @reporters_for_filter = User.where(id: Defect.where(id: unfiltered_ids)
      .select('DISTINCT created_by'))
      .order(:first_name, :last_name)

    # Only show update button if user explicitly clicked "Apply" from a saved filter
    # This prevents the button from showing on every page load
    @matched_filter = nil
    if params[:filter_id].present?
      # User came from defect_filters#index - show update button
      @matched_filter = current_user.defect_filters.active.find_by(id: params[:filter_id])
    end

    # Load default defect assignee
    @default_defect_assignee = DefaultDefectAssignee.where(archive_status: false).first

    # APPLY detail-level filters BEFORE pagination so counts/pages are correct
    @defects = @defects.where(retest_count: params[:retest_count]) if params[:retest_count].present?

    if params[:reopened_count].present?
      # Filter defects by the exact number of times they were moved to "Reopened"
      # Use a subquery to avoid loading IDs into Ruby and to keep it DB-side
      desired_count = params[:reopened_count].to_i
      filtered_ids_subquery = DefectHistory
        .where(history_type: 'Status Changed')
        .where('history ILIKE ?', '%to Reopened%')
        .where(defect_id: @defects.except(:select, :order, :limit, :offset).select(:id))
        .group(:defect_id)
        .having('COUNT(*) = ?', desired_count)
        .select(:defect_id)
      @defects = @defects.where(id: filtered_ids_subquery)
    end

    # Pagination
    @per_page = 20
    @page = (params[:page] || 1).to_i
    total = @defects.except(:select, :group, :order).count
    @total_count = total.is_a?(Hash) ? total.size : total
    @total_pages = (@total_count / @per_page.to_f).ceil
    @start_count = ((@page - 1) * @per_page) + 1
    @end_count = [@page * @per_page, @total_count].min
    @defects = @defects.offset((@page - 1) * @per_page).limit(@per_page)

    # If we skipped eager loading earlier due to GROUP BY, add it back now after pagination
    # to avoid N+1 queries when rendering the view
    if skip_eager_loading
      # For assignee sorting, we need to preserve the SELECT clause when getting IDs
      # Use select(:id) instead of pluck to maintain the ORDER BY with computed columns
      defect_ids = @defects.select('defects.id').map(&:id)
      @defects = Defect.where(id: defect_ids)
        .includes(:users, :labels, :statuses, :qa_module, :banking_type, product: %i[client groupwares])
        .order(Arel.sql("array_position(ARRAY[#{defect_ids.join(',')}]::bigint[], defects.id)"))
    end

    # All details show all
    # (moved to above pagination)
    # @defects = @defects.where(retest_count: params[:retest_count]) if params[:retest_count].present?
    # @defects = @defects.where(reopened_count: params[:reopened_count]) if params[:reopened_count].present?

    # Compute reopened count per defect for the defects on the current page
    defect_ids_for_page = @defects.map(&:id)
    @reopened_counts = if defect_ids_for_page.any?
                         DefectHistory.where(defect_id: defect_ids_for_page, history_type: 'Status Changed')
                           .where('history ILIKE ?', '%to Reopened%')
                           .group(:defect_id)
                           .count
                       else
                         {}
                       end

    render :index_show
  end

  def show
    # @defect is already set by set_defect before_action
    # Authorization is handled by CanCanCan ability system

    # Prevent viewing drafts created by other users
    if @defect.draft? && @defect.created_by != current_user.id
      redirect_to defect_index_path, alert: 'You do not have permission to view this draft defect.'
      return
    end

    @reopened_count = DefectHistory.where(defect_id: @defect.id, history_type: 'Status Changed')
      .select { |history| history.new_value == 'Reopened' }
      .size

    # Preserve product_id for back navigation
    @product_id = params[:product_id] || @defect.product_id

    # For draft defects, back button should go to drafts page with product filter
    # For published defects, use referrer or index_show with product filter
    if @defect.draft?
      # Draft defects should return to drafts page
      @return_path = drafts_defect_index_path
    else
      # Store the referrer for proper back navigation if it's from index_show
      session[:defect_return_path] = request.referer if request.referer&.include?('index_show') || request.referer&.include?('/defect?')

      # Get the return path from session or construct default
      @return_path = session[:defect_return_path] || index_show_defect_index_path(product_id: @product_id)
    end

    qa_user_ids = User.joins(:roles)
      .where(roles: { name: 'qa' })
      .pluck(:id)

    product_user_ids = if @defect.product.present?
                         @defect.craftsilicon_users
                           .where.not(id: @defect.users.pluck(:id))
                           .where(id: @defect.product.users.pluck(:id))
                           .pluck(:id)
                       else
                         []
                       end

    @available_users = User.where(id: qa_user_ids + product_user_ids)
      .distinct
      .order(:first_name, :last_name)

    # Defects History
    @defects_history = DefectHistory.where(defect_id: @defect.id).order(created_at: :desc)

    @timeline_items = @defect.timeline_items(order: :desc)

    # Attachment paginations
    @attachments_per_page = 6
    @attachments_page = (params[:attachments_page] || 1).to_i
    all_attachments = @defect.all_attachments.sort_by do |a|
      if a.respond_to?(:created_at)
        a.created_at
      elsif a.respond_to?(:attachable) && a.attachable.respond_to?(:created_at)
        a.attachable.created_at
      else
        Time.current
      end
    end.reverse
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
    # @defect.product_id ||= params[:product_id] if params[:product_id].present?
    # @defect.qa_module_id ||= params[:qa_module_id] if params[:qa_module_id].present?
    # @defect.submodule_id ||= params[:submodule_id] if params[:submodule_id].present?

    @defect.product_id = params[:product_id] if Defect.column_names.include?('product_id') && params[:product_id].present?

    @defect.qa_module_id = params[:qa_module_id] if Defect.column_names.include?('qa_module_id') && params[:qa_module_id].present?

    @defect.submodule_id = params[:submodule_id] if Defect.column_names.include?('submodule_id') && params[:submodule_id].present?

    # Clean user_ids coming from hidden field (will be [""] if none selected)
    selected_user_ids = Array(params[:defect][:user_ids]).reject(&:blank?)

    # Explicitly set draft flag BEFORE assignment logic
    @defect.draft = params[:commit] == 'draft'

    # Fallback to global default assignee if no one selected (but NOT for drafts)
    if selected_user_ids.blank? && !@defect.draft?
      default_assignee = DefaultDefectAssignee.where(archive_status: false)
        .order(created_at: :desc)
        .first
      selected_user_ids = [default_assignee.user_id.to_s] if default_assignee&.user_id.present?
    end

    # Assign before saving
    @defect.user_ids = selected_user_ids

    if @defect.save
      if @defect.draft?
        redirect_to index_show_defect_index_path(product_id: @defect.product_id), notice: 'Draft defect saved successfully.'
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
          "Assignee changed from None to #{assigned_names} by #{current_user.name}"
        )

        redirect_to @defect, notice: 'Defect was successfully created.'
        # Send An email to the creator and the assignee
        # Send An email to the creator and the assignee
        # app/controllers/defects_controller.rb
        @defect.users.each do |user|
          Messaging::EmailSender.send_email(
            'New Defect',
            to: [user.email],
            actor: current_user,
            priority: :normal,
            type: 'new_defect'
          ).use_template(
            view: 'user_mailer/new_defect_email',
            assigns: { defect: @defect, creator: current_user }
          ).set_source('defect', @defect.id).set_party('user', user.id).send(queue: true)
        end
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
    # @defect is already set by set_defect before_action

    # Prevent editing drafts created by other users
    if @defect.draft? && @defect.created_by != current_user.id
      redirect_to defect_index_path, alert: 'You do not have permission to edit this draft defect.'
      return
    end

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

    # Set selected product from defect (same pattern as new action)
    # This ensures banking types are loaded correctly
    @selected_product = if params[:product_id].present?
                          Product.find_by(id: params[:product_id])
                        elsif @defect.product_id.present?
                          @defect.product
                        end

    # Use set_form_data to load statuses, modules, banking types, etc. consistently with new action
    set_form_data

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

    # Load parent modules for the Module dropdown (keep existing logic for edit)
    @qa_modules = if @defect.product_id.present?
                    QaModule.where(product_id: @defect.product_id, parent_id: nil).order(:name)
                  else
                    QaModule.where(parent_id: nil).order(:name)
                  end

    # Explicitly load banking types for the defect's product (fixes missing banking types in edit form)
    @banking_types = if @defect.product_id.present?
                       BankingType.for_product(@defect.product_id).order(:name)
                     else
                       BankingType.all.order(:name)
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
    # Prevent updating drafts created by other users
    if @defect.draft? && @defect.created_by != current_user.id
      redirect_to defect_index_path, alert: 'You do not have permission to update this draft defect.'
      return
    end

    audit_on_update(@defect)

    # Track changes before update for detailed notifications
    changes_to_track = track_defect_changes(@defect, defect_params)

    selected_user_ids = params[:defect][:user_ids]
    original_user_ids = @defect.user_ids.dup

    # Check if this is a "Save as Draft" or "Publish" action
    is_draft_save = params[:commit] == 'draft'
    is_publish = params[:commit] == 'publish'

    # If publishing a draft, set draft to false before update
    @defect.draft = false if is_publish && @defect.draft?

    if @defect.update(defect_params.except(:attachments))
      # Attach new files without removing old ones
      if params[:defect][:attachments].present?
        params[:defect][:attachments].each do |file|
          @defect.attachments.attach(file)
        end
      end

      # Track assignee changes
      if selected_user_ids != original_user_ids
        assignee_changes = track_assignee_changes(original_user_ids, selected_user_ids)
        changes_to_track.merge!(assignee_changes) if assignee_changes.any?
      end

      @defect.user_ids = selected_user_ids

      # Process mentions in updated defect content asynchronously (only for published defects)
      unless @defect.draft?
        ProcessMentionsJob.perform_later(
          @defect.content&.body&.to_html,
          @defect.id,
          current_user.id,
          'defect_content'
        )
      end

      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.update')
        .log("Updated Defect ##{@defect.id}")

      # Log detailed changes to history and send notifications
      log_defect_changes(changes_to_track) unless is_draft_save

      # Handle redirects based on action
      if is_draft_save
        redirect_to index_show_defect_index_path(product_id: @defect.product_id), notice: 'Draft saved successfully.'
      elsif is_publish
        redirect_to @defect, notice: 'Defect was successfully published.'
      else
        redirect_to @defect, notice: 'Defect was successfully updated.'
      end

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
      @defect.users.each do |user|
        Messaging::EmailSender.send_email(
          "Defect with Defect ID #{@defect.defect_unique} deleted",
          to: [user.email],
          actor: current_user,
          priority: :normal,
          type: 'defect_deleted'
        ).use_template(
          view: 'user_mailer/defect_deleted_email',
          assigns: { defect: @defect, current_user: current_user }
        ).set_source('defect', @defect.id).set_party('user', user.id).send(queue: true)
      end
    else
      @defect.destroy
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.hard_delete')
        .log("Hard-deleted Defect ##{@defect.id}")
    end
    redirect_to index_show_defect_index_path(product_id: @defect.product_id), notice: 'Defect was successfully deleted.'
  end

  # add a user to the defect
  def add_defect
    if @defect.users.include?(User.find(params[:user_id]))
      redirect_to @defect, notice: 'User has already been assigned.'
    else
      user = User.find(params[:user_id])

      # Capture old assignees BEFORE changing
      old_assignees = @defect.users.map(&:name).join(', ').presence || 'None'

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
        @defect,
        current_user,
        'Assigned to',
        "Assignee changed from #{old_assignees} to #{user.name} by #{current_user.name}"
      )
    end
  end

  def drafts
    # Only show drafts created by the current user
    @defects = Defect.drafts
      .where(created_by: current_user.id)
      .includes(:users, :qa_module, :submodule)
      .order(updated_at: :desc)

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

    # Initialize assignees and reporters (required for filter dropdowns)
    @assignees_for_filter = User.joins(:defects)
      .where(defects: { id: @defects.except(:select, :order, :limit, :offset).select(:id) })
      .distinct
      .order(:first_name, :last_name)

    @reporters_for_filter = User.where(id: Defect.where(id: @defects.except(:select, :order, :limit, :offset).select(:id))
      .select('DISTINCT created_by'))
      .order(:first_name, :last_name)

    # Compute reopened count per defect for the defects on the current page
    defect_ids_for_page = @defects.map(&:id)
    @reopened_counts = if defect_ids_for_page.any?
                         DefectHistory.where(defect_id: defect_ids_for_page, history_type: 'Status Changed')
                           .where('history ILIKE ?', '%to Reopened%')
                           .group(:defect_id)
                           .count
                       else
                         {}
                       end

    render :index_show
  end

  def publish
    @defect = Defect.find(params[:id])

    # Only allow publishing drafts created by the current user
    if @defect.draft? && @defect.created_by != current_user.id
      redirect_to defect_index_path, alert: 'You do not have permission to publish this draft defect.'
      return
    end

    # Sequential ID is automatically generated by before_update callback in the model
    if @defect.update(draft: false)
      log_event(
        @defect,
        current_user,
        'Defect Published',
        "Defect ##{@defect.id} was published by #{current_user.name} at #{Time.now.strftime('%H:%M on %d-%m-%Y')}"
      )
      redirect_to @defect, notice: 'Defect has been published successfully.'
    else
      redirect_to @defect, alert: 'Failed to publish defect.'
    end
  end

  def defect_status
    # Check if defect is blocked by another defect
    # Removed blocking check - users can now change status even when defects are blocked

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

    # Capture old status BEFORE changing
    old_status_name = @defect.statuses.first&.name || 'None'

    # Proceed with normal status change
    @defect.transaction do
      @defect.statuses.clear
      @defect.statuses << status

      # Log event with from/to format
      log_event(
        @defect,
        current_user,
        'Status Changed',
        "Status changed from #{old_status_name} to #{status.name} by #{current_user.name}"
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

    # Capture old assignees BEFORE removing
    old_assignees = @defect.users.map(&:name).join(', ')

    @defect.users.delete(user)

    # New assignees after removal
    new_assignees = @defect.users.map(&:name).join(', ').presence || 'None'

    activity('user_activity')
      .caused_by(current_user)
      .performed_on(@defect)
      .event('defect.unassign_user')
      .with_properties(user_id: user.id)
      .log("Unassigned #{user.name} from Defect ##{@defect.id}")

    log_event(
      @defect,
      current_user,
      'Unassigned',
      "Assignee changed from #{old_assignees} to #{new_assignees} by #{current_user.name}"
    )

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
    # Capture old priority BEFORE changing
    old_priority = @defect.priority || 'None'

    if @defect.update(priority: params[:defect][:priority])
      activity('user_activity')
        .caused_by(current_user)
        .performed_on(@defect)
        .event('defect.update_priority')
        .with_properties(priority: @defect.priority)
        .log("Updated priority to #{@defect.priority} for Defect ##{@defect.id}")

      # Add history log and trigger notification
      log_event(
        @defect,
        current_user,
        'Priority Updated',
        "Priority changed from #{old_priority} to #{@defect.priority}"
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

      # History log — will automatically send the notification
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
      # Log and notify
      log_event(
        @defect,
        current_user,
        'Defect Unlinked',
        "Unlinked #{@defect.defect_unique} from #{target_defect.defect_unique} by #{current_user.name} at #{Time.now.strftime('%H:%M on %d-%m-%Y')}"
      )

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

    # Start with a scope matching what index_show shows (published + includes for joins)
    defects = Defect.published
      .includes(:users, :qa_module, :labels, :banking_type, :statuses, product: %i[client groupwares])

    # Client/Product filters (exact client name match when both provided)
    if params[:client_name].present? && params[:product_id].present?
      defects = defects.joins(product: :client)
        .where('LOWER(clients.name) = ?', params[:client_name].to_s.downcase.strip)
        .where(products: { id: params[:product_id] })
    elsif params[:client_name].present?
      defects = defects.joins(product: :client)
        .where('LOWER(clients.name) = ?', params[:client_name].to_s.downcase.strip)
    elsif params[:product_id].present?
      defects = defects.where(product_id: params[:product_id])
    end

    # Restrict for non-admin/observer/qa users
    defects = defects.joins(:users).where(users: { id: current_user.id }) unless current_user.has_any_role?(:admin, :observer, :qa)

    # Status filter (multiple values, case-insensitive)
    selected_statuses = Array(params[:status]).reject(&:blank?)
    if selected_statuses.any?
      downcased = selected_statuses.map { |s| s.to_s.downcase }
      defects = defects.joins(:statuses).where('LOWER(statuses.name) IN (?)', downcased)
    end

    # Labels filter (multi-select by id)
    selected_labels = Array(params[:label_ids]).reject(&:blank?)
    defects = defects.joins(:labels).where(labels: { id: selected_labels }) if selected_labels.any?

    # Priority filter (multiple values - matches index_show)
    selected_priorities = Array(params[:priority]).reject(&:blank?)
    defects = defects.where(defects: { priority: selected_priorities }) if selected_priorities.any?

    # Assignee filter
    defects = defects.joins(:users).where(users: { id: params[:user_id] }) if params[:user_id].present?

    # Reporter filter (creator_id/created_by)
    selected_reporters = Array(params[:reporter_id]).reject(&:blank?)
    defects = defects.where(created_by: selected_reporters) if selected_reporters.any?

    # Module/Submodule filtering - matches index_show logic exactly
    qa_module_ids = Array(params[:qa_module_id]).reject(&:blank?)
    submodule_ids = Array(params[:submodule_id]).reject(&:blank?)

    if qa_module_ids.any? && submodule_ids.any?
      # Both parent modules and submodules selected
      submodule_defects = defects.where(qa_module_id: submodule_ids)

      if submodule_defects.exists?
        defects = submodule_defects
      else
        parent_module_defects = defects.where(qa_module_id: qa_module_ids)
        defects = parent_module_defects.exists? ? parent_module_defects : submodule_defects
      end
    elsif qa_module_ids.any?
      # Only parent modules selected - include all their submodules
      parent_modules = QaModule.where(id: qa_module_ids)
      if parent_modules.any?
        submodule_ids_for_parents = QaModule.where(parent_id: qa_module_ids).pluck(:id)
        all_module_ids = qa_module_ids + submodule_ids_for_parents
        defects = defects.where(qa_module_id: all_module_ids)
      else
        defects = defects.where(qa_module_id: qa_module_ids)
      end
    elsif submodule_ids.any?
      # Only submodules selected without parent modules
      defects = defects.where(qa_module_id: submodule_ids)
    end

    # Banking type filter (multiple values)
    banking_type_ids = Array(params[:banking_type_id]).reject(&:blank?)
    defects = defects.where(banking_type_id: banking_type_ids) if banking_type_ids.any?

    # Date range filters (parse dates defensively)
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

    # Full-text / free-text search across related tables
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

    # Ordering and uniqueness
    # Sort by the numeric part of defect_unique (e.g. KCBL-123 -> 123) to ensure natural order
    direction = %w[asc desc].include?(params[:order]) ? params[:order] : 'asc'

    # Fix PG::InvalidColumnReference: Use subquery to separate filtering (distinct) from ordering
    filtered_ids = defects.except(:order).distinct.select(:id)

    defects = Defect.where(id: filtered_ids)
      .includes(:users, :qa_module, :labels, :banking_type, :statuses, product: %i[client groupwares])
      .order(Arel.sql("CAST(NULLIF(SPLIT_PART(defect_unique, '-', 2), '') AS INTEGER) #{direction}"))
    defect_ids = defects.map(&:id)
    reopened_counts = if defect_ids.any?
                        DefectHistory.where(defect_id: defect_ids, history_type: 'Status Changed')
                          .where('history ILIKE ?', '%to Reopened%')
                          .group(:defect_id)
                          .count
                      else
                        {}
                      end

    # Generate CSV
    csv_data = CSV.generate(headers: true) do |csv|
      csv << [
        'Defect ID', 'Status', 'Summary', 'Priority', 'Module', 'Sub Module',
        'Banking Types', 'Labels', 'Assignee', 'Reporter', 'Project',
        'Created At', 'Retest Count', 'Reopened Count'
      ]

      defects.each do |defect|
        client_and_groupware = [defect.product.client&.name, defect.product.groupwares.first&.name].compact.join(' - ')
        reopened_count = reopened_counts[defect.id] || 0
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
          defect.created_at.strftime('%Y-%m-%d %H:%M'),
          defect.retest_count,
          reopened_count

        ]
      end
    end

    # Use a filesystem-safe timestamp format for filename
    send_data csv_data, filename: "defects_#{Time.zone.now.strftime('%Y%m%d_%H%M%S')}.csv", type: 'text/csv'
  end

  def defects_download_excel
    # Base scope (published defects) - include all necessary associations
    defects = Defect.published
      .includes(:users, :labels, :statuses, :qa_module, :submodule, :banking_type, product: %i[client groupwares])

    # Apply the same filters as index_show for consistency
    product_ids = Array(params[:product_id]).reject(&:blank?)

    # Client filter (exact, case-insensitive, and scoped by product_id)
    if params[:client_name].present? && product_ids.any?
      defects = defects.joins(product: :client)
        .where('LOWER(clients.name) = ?', params[:client_name].to_s.downcase.strip)
        .where(products: { id: product_ids })
    elsif params[:client_name].present?
      defects = defects.joins(product: :client)
        .where('LOWER(clients.name) = ?', params[:client_name].to_s.downcase.strip)
    elsif product_ids.any?
      defects = defects.where(product_id: product_ids)
    end

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

    # Priority filter (multiple values - matches index_show)
    selected_priorities = Array(params[:priority]).reject(&:blank?)
    defects = defects.where(defects: { priority: selected_priorities }) if selected_priorities.any?

    # Assignee filter
    defects = defects.joins(:users).where(users: { id: params[:user_id] }) if params[:user_id].present?

    # Reporter filter (creator_id/created_by)
    selected_reporters = Array(params[:reporter_id]).reject(&:blank?)
    defects = defects.where(created_by: selected_reporters) if selected_reporters.any?

    # Module/Submodule filtering - matches index_show logic exactly
    qa_module_ids = Array(params[:qa_module_id]).reject(&:blank?)
    submodule_ids = Array(params[:submodule_id]).reject(&:blank?)

    if qa_module_ids.any? && submodule_ids.any?
      # Both parent modules and submodules selected
      submodule_defects = defects.where(qa_module_id: submodule_ids)

      if submodule_defects.exists?
        defects = submodule_defects
      else
        parent_module_defects = defects.where(qa_module_id: qa_module_ids)
        defects = parent_module_defects.exists? ? parent_module_defects : submodule_defects
      end
    elsif qa_module_ids.any?
      # Only parent modules selected - include all their submodules
      parent_modules = QaModule.where(id: qa_module_ids)
      if parent_modules.any?
        submodule_ids_for_parents = QaModule.where(parent_id: qa_module_ids).pluck(:id)
        all_module_ids = qa_module_ids + submodule_ids_for_parents
        defects = defects.where(qa_module_id: all_module_ids)
      else
        defects = defects.where(qa_module_id: qa_module_ids)
      end
    elsif submodule_ids.any?
      # Only submodules selected without parent modules
      defects = defects.where(qa_module_id: submodule_ids)
    end

    # Banking type filter (multiple values)
    banking_type_ids = Array(params[:banking_type_id]).reject(&:blank?)
    defects = defects.where(banking_type_id: banking_type_ids) if banking_type_ids.any?

    # Date range filters
    start_date = params[:start_date].presence
    end_date = params[:end_date].presence
    begin
      if start_date.present? && end_date.present?
        from = Date.parse(start_date).beginning_of_day
        to = Date.parse(end_date).end_of_day
        defects = defects.where(defects: { created_at: from..to })
      elsif start_date.present?
        from = Date.parse(start_date).beginning_of_day
        defects = defects.where('defects.created_at >= ?', from)
      elsif end_date.present?
        to = Date.parse(end_date).end_of_day
        defects = defects.where('defects.created_at <= ?', to)
      end
    rescue ArgumentError
      # Ignore invalid dates without breaking
    end

    # Full-text search across related tables
    if params[:query].present?
      q = "%#{params[:query].to_s.strip}%"
      defects = defects.left_joins(:users, :qa_module, :submodule, :banking_type, product: %i[client groupwares]).where(
        "defects.summary ILIKE :q
        OR defects.defect_unique ILIKE :q
        OR defects.priority ILIKE :q
        OR users.first_name ILIKE :q
        OR users.last_name ILIKE :q
        OR clients.name ILIKE :q
        OR groupwares.name ILIKE :q
        OR qa_modules.name ILIKE :q
        OR submodules.name ILIKE :q
        OR banking_types.name ILIKE :q",
        q: q
      )
    end

    # Ordering
    # Sort by the numeric part of defect_unique (e.g. KCBL-123 -> 123) to ensure natural order
    direction = %w[asc desc].include?(params[:order]) ? params[:order] : 'asc'

    # Fix PG::InvalidColumnReference: Use subquery to separate filtering (distinct) from ordering
    filtered_ids = defects.except(:order).distinct.select(:id)

    defects = Defect.where(id: filtered_ids)
      .includes(:users, :labels, :statuses, :qa_module, :submodule, :banking_type, product: %i[client groupwares])
      .order(Arel.sql("CAST(NULLIF(SPLIT_PART(defect_unique, '-', 2), '') AS INTEGER) #{direction}"))

    # Restrict for non-admin/observer/qa users (same as index_show)
    defects = defects.joins(:users).where(users: { id: current_user.id }) unless current_user.has_any_role?(:admin, :observer, :qa)

    # Precompute reopened counts for all defects to avoid N+1 queries
    defect_ids = defects.map(&:id)
    reopened_counts = if defect_ids.any?
                        DefectHistory.where(defect_id: defect_ids, history_type: 'Status Changed')
                          .where('history ILIKE ?', '%to Reopened%')
                          .group(:defect_id)
                          .count
                      else
                        {}
                      end

    # Build Excel via Axlsx (caxlsx)
    package = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: 'Defects') do |sheet|
      # Headers with ALL available columns including the new associations
      sheet.add_row [
        'Defect ID',
        'Status',
        'Summary',
        'Priority',
        'Issue Type',
        'Module', # From qa_module association
        'Sub Module', # From submodule association
        'Banking Type', # From banking_type association
        'Retest Count',
        'Reopened Count',
        'Labels',
        'Assignee',
        'Reporter',
        'Project',
        'Created At'
      ]

      defects.each do |defect|
        client_name = defect.product&.client&.name
        groupware_name = defect.product&.groupwares&.first&.name
        client_and_groupware = [client_name, groupware_name].compact.join(' - ')
        reopened_count = reopened_counts[defect.id] || 0

        sheet.add_row [
          defect.defect_unique,
          defect.statuses.map(&:name).join(', '),
          defect.summary,
          defect.priority,
          defect.issue_type,
          defect.qa_module&.name, # New association
          defect.submodule&.name, # New association (submodule QaModule)
          defect.banking_type&.name, # New association
          defect.retest_count,
          reopened_count,
          defect.labels.map(&:name).join(', '),
          defect.users.map { |u| "#{u.first_name} #{u.last_name}" }.join(', '),
          defect.creator&.name,
          client_and_groupware,
          defect.created_at.strftime('%Y-%m-%d %H:%M')
          # defect.start_date&.strftime('%Y-%m-%d'),
          # defect.end_date&.strftime('%Y-%m-%d'),
          # defect.description
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
      # Log and notify
      log_event(
        @defect,
        current_user,
        'Defect Linked',
        "Linked #{@defect.defect_unique} as blocked by #{target_defect.defect_unique} by #{current_user.name} at #{Time.now.strftime('%H:%M on %d-%m-%Y')}"
      )

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
          # Log each addition (and trigger the notification)
          log_event(
            @defect,
            current_user,
            'Attachment Added',
            "Added attachment #{attachment.original_filename} by #{current_user.name} at #{Time.now.strftime('%H:%M on %d-%m-%Y')}"
          )
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
    attachment_id = attachment.id
    filename = attachment.blob.filename.to_s
    attachment.purge

    log_event(@defect, current_user, 'remove_attachment', "Removed attachment #{filename}")

    respond_to do |format|
      format.json { head :no_content }
      format.turbo_stream { render turbo_stream: turbo_stream.remove("attachment_#{attachment_id}") }
      format.js { render js: "document.getElementById('attachment_#{attachment_id}').remove();" }
      format.html { redirect_to defect_path(@defect), notice: 'File was successfully removed.' }
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.json { render json: { error: 'File or defect not found' }, status: :not_found }
      format.turbo_stream { render turbo_stream: turbo_stream.replace('flash', partial: 'layouts/flash', locals: { alert: 'File or defect not found.' }) }
      format.js { render js: "alert('File or defect not found.');" }
      format.html { redirect_to defects_path, alert: 'File or defect not found.' }
    end
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

  # Helper method to normalize filter parameters for comparison
  def normalize_filter_params(params_hash)
    return {} if params_hash.blank?

    normalized = {}
    params_hash.each do |key, value|
      next if value.blank? || value == []

      # Convert arrays to sorted arrays for consistent comparison
      normalized[key] = if value.is_a?(Array)
                          value.reject(&:blank?).sort
                        elsif value.is_a?(String)
                          value.strip
                        else
                          value
                        end
    end

    normalized
  end

  def apply_defect_filters(defects)
    # Start with base ordering
    defects = defects.order(created_at: params[:order] == 'asc' ? :asc : :desc)

    # Date range filters
    defects = defects.where('defects.created_at >= ?', params[:start_date].to_date.beginning_of_day) if params[:start_date].present?

    defects = defects.where('defects.created_at <= ?', params[:end_date].to_date.end_of_day) if params[:end_date].present?

    # NOTE: The individual array filters (status, priority, user_id, etc.)
    # are now handled in the main index action to ensure proper ordering

    defects
  end

  def find_matching_saved_filter(current_params)
    # Get all active saved filters for current user
    saved_filters = current_user.defect_filters.active

    return nil if saved_filters.blank?

    # Build current filter hash from params
    current_filter = extract_filter_params(current_params)

    # Return nil if no filters are active
    return nil if current_filter.empty?

    # Check each saved filter for a match
    saved_filters.each do |filter|
      return filter if filters_match?(filter.filters || {}, current_filter)
    end

    nil
  end

  def extract_filter_params(params)
    # Extract only filter-related parameters

    extracted = {}

    # Collect array parameters
    %w[status priority user_id reporter_id label_ids qa_module_id submodule_id banking_type_id].each do |key|
      values = Array(params[key]).reject(&:blank?).map(&:to_s).sort
      extracted[key] = values if values.any?
    end

    # Collect single value parameters
    %w[order start_date end_date query client_name].each do |key|
      extracted[key] = params[key].to_s if params[key].present?
    end

    extracted
  end

  def filters_match?(saved_filters, current_filters)
    # Normalize both filter sets for comparison
    saved_normalized = normalize_filters(saved_filters)
    current_normalized = normalize_filters(current_filters)

    # Check if they have the same keys
    return false if saved_normalized.keys.sort != current_normalized.keys.sort

    # Check if all values match
    saved_normalized.each do |key, value|
      current_value = current_normalized[key]

      # Handle array comparisons
      if value.is_a?(Array) && current_value.is_a?(Array)
        return false if value.map(&:to_s).sort != current_value.map(&:to_s).sort
      elsif value.to_s.downcase != current_value.to_s.downcase
        return false
      end
    end

    true
  end

  def normalize_filters(filters)
    # Convert all values to lowercase strings for case-insensitive comparison
    normalized = {}

    filters.each do |key, value|
      if value.is_a?(Array)
        normalized[key] = value.map { |v| v.to_s.downcase }
      elsif value.present?
        normalized[key] = value.to_s.downcase
      end
    end

    normalized
  end

  def authorize_view_failure_reports!
    return if current_user.has_role?(:qa) || current_user.has_role?(:hod) || current_user.has_role?(:admin)

    redirect_to defect_path(@defect), notice: 'You are not authorized to view failure reports.'
  end

  def set_form_data
    # selected product if provided in params (used to scope modules/banking types)
    # Also use @defect.product if we're editing a defect
    @selected_product = if params[:product_id].present?
                          Product.find_by(id: params[:product_id])
                        elsif defined?(@defect) && @defect&.product_id.present?
                          @defect.product
                        end

    # QA modules (parent modules) - scoped to selected product if present
    @qa_modules = if @selected_product
                    QaModule.where(product_id: @selected_product.id, parent_id: nil).order(:name)
                  else
                    QaModule.where(parent_id: nil).order(:name)
                  end

    # banking types scoped to selected product (so UI can show only product banking types)
    @banking_types = if @selected_product
                       BankingType.for_product(@selected_product.id)
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
    defect_id = (params[:defect_id] || params[:id]).to_s.strip

    # First, try to find by defect_unique (bug number like "ISP-0045")
    @defect = Defect.find_by(defect_unique: defect_id)

    # If not found, check if it looks like a UUID (contains hyphens)
    if @defect.nil? && defect_id.include?('-')
      # Clean up malformed UUID (remove trailing characters)
      # UUID format: 8-4-4-4-12 characters
      uuid_pattern = /^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/i
      if defect_id.match?(uuid_pattern)
        clean_uuid = defect_id.match(uuid_pattern)[1]
        @defect = Defect.find_by(id: clean_uuid)
      end
    end

    # If still not found, use find! to raise proper Rails 404
    return unless @defect.nil?

    Defect.find(defect_id)
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

    # Automatically trigger a user email notification
    # Convert history_type to a clean action name (e.g., "Priority Updated" -> "priority_updated")
    action_name = history_type.parameterize.underscore

    defect.users.each do |recipient|
      title = UserMailer::ACTION_TITLES[action_name] || action_name.titleize
      subject_text = "[Defect #{defect.defect_unique}] #{title} by #{user.name}"
      # the creator of the defect on the defect there is user_id

      Messaging::EmailSender.send_email(
        subject_text,
        to: [recipient.email, user.email, defect.creator.email],
        actor: user,
        priority: :normal,
        type: 'defect_action'
      ).use_template(
        view: 'user_mailer/defect_action_email',
        assigns: { defect: defect, actor: user, action_name: action_name, url: defect_url(@defect, Rails.application.config.action_mailer.default_url_options) }
      ).set_source('defect', defect.id).set_party('user', recipient.id).send(queue: true)
    end
  end

  def track_defect_changes(defect, params)
    changes = {}

    # Track summary changes
    changes[:summary] = { from: defect.summary, to: params[:summary] } if params[:summary].present? && params[:summary] != defect.summary

    # Track content/description changes (ActionText)
    if params[:content].present?
      current_content = defect.content&.body.to_s
      new_content = params[:content].to_s

      # Normalize HTML for semantic comparison (ignore whitespace/formatting differences)
      normalized_current = normalize_html(current_content)
      normalized_new = normalize_html(new_content)

      # Only track if content actually changed semantically
      if normalized_current != normalized_new && normalized_new.present?
        # Keep HTML formatting for rich text display in history
        # Convert to plain string for Sidekiq/JSON serialization
        changes[:description] = { from: current_content.to_s, to: new_content.to_s }
      end
    end

    # Track priority changes
    changes[:priority] = { from: defect.priority, to: params[:priority] } if params[:priority].present? && params[:priority] != defect.priority

    # Track status changes (using status_id)
    if params[:status_id].present?
      current_status_id = defect.statuses.first&.id.to_s
      new_status_id = params[:status_id].to_s
      if current_status_id != new_status_id
        current_status_name = defect.statuses.first&.name || 'None'
        new_status_name = Status.find_by(id: new_status_id)&.name || 'Unknown'
        changes[:status] = { from: current_status_name, to: new_status_name }
      end
    end

    # Track banking type changes - only if value changed
    if params[:banking_type_id].present?
      current_banking_type_id = defect.banking_type_id.to_s
      new_banking_type_id = params[:banking_type_id].to_s
      if current_banking_type_id != new_banking_type_id
        current_banking_type = defect.banking_type&.name || 'None'
        new_banking_type = BankingType.find_by(id: new_banking_type_id)&.name || 'Unknown'
        changes[:banking_type] = { from: current_banking_type, to: new_banking_type }
      end
    end

    # Track module changes - only if value changed
    if params[:qa_module_id].present?
      current_module_id = defect.qa_module_id.to_s
      new_module_id = params[:qa_module_id].to_s
      if current_module_id != new_module_id
        current_module = defect.qa_module&.name || 'None'
        new_module = QaModule.find_by(id: new_module_id)&.name || 'Unknown'
        changes[:module] = { from: current_module, to: new_module }
      end
    end

    # Track submodule changes - only if value changed
    if params[:submodule_id].present?
      current_submodule_id = defect.submodule_id.to_s
      new_submodule_id = params[:submodule_id].to_s
      if current_submodule_id != new_submodule_id
        current_submodule = defect.submodule&.name || 'None'
        new_submodule = QaModule.find_by(id: new_submodule_id)&.name || 'Unknown'
        changes[:submodule] = { from: current_submodule, to: new_submodule }
      end
    end

    # Track label changes - only if actually changed
    if params[:label_ids].present?
      current_label_ids = defect.label_ids.map(&:to_s).sort
      new_label_ids = params[:label_ids].reject(&:blank?).map(&:to_s).sort
      changes[:labels] = { from: current_label_ids, to: new_label_ids } if new_label_ids != current_label_ids
    end

    changes
  end

  def track_assignee_changes(original_user_ids, new_user_ids)
    changes = {}

    original_ids = original_user_ids.sort
    new_ids = new_user_ids.map(&:to_i).sort

    changes[:assignees] = { from: original_ids, to: new_ids } if original_ids != new_ids

    changes
  end

  def log_defect_changes(changes_hash)
    return if changes_hash.empty?

    # Log each type of change to history for detailed tracking
    changes_hash.each do |field, change_data|
      history_type = case field
                     when :summary then 'Summary Updated'
                     when :description then 'Description Updated'
                     when :priority then 'Priority Updated'
                     when :status then 'Status Updated'
                     when :severity then 'Severity Updated'
                     when :labels then 'Labels Updated'
                     when :assignees then 'Assignees Updated'
                     when :banking_type then 'Banking Type Updated'
                     when :module then 'Module Updated'
                     when :submodule then 'Submodule Updated'
                     else 'General Update'
                     end

      history_details = build_change_details(field, change_data)

      DefectHistory.create!(
        defect: @defect,
        user: current_user,
        history_type: history_type,
        history: history_details,
        created_at: Time.current
      )
    end

    # Send targeted notification emails based on change types
    send_edit_notifications(changes_hash)
  end

  def build_change_details(field, change_data)
    case field
    when :summary
      "#{change_data[:from]} → #{change_data[:to]}"
    when :description
      if change_data[:from].present? && change_data[:to].present?
        "#{change_data[:from]} → #{change_data[:to]}"
      else
        'Description updated'
      end
    when :priority
      "#{change_data[:from]} → #{change_data[:to]}"
    when :status
      "#{change_data[:from]} → #{change_data[:to]}"
    when :severity
      "#{change_data[:from]} → #{change_data[:to]}"
    when :banking_type
      "#{change_data[:from]} → #{change_data[:to]}"
    when :module
      "#{change_data[:from]} → #{change_data[:to]}"
    when :submodule
      "#{change_data[:from]} → #{change_data[:to]}"
    when :labels
      old_labels = Label.where(id: change_data[:from]).pluck(:name).join(', ')
      new_labels = Label.where(id: change_data[:to]).pluck(:name).join(', ')
      "#{old_labels.presence || 'None'} → #{new_labels.presence || 'None'}"
    when :assignees
      old_users = User.where(id: change_data[:from]).pluck(:name).join(', ')
      new_users = User.where(id: change_data[:to]).pluck(:name).join(', ')
      "#{old_users.presence || 'None'} → #{new_users.presence || 'None'}"
    else
      "#{field.to_s.humanize} changed"
    end
  end

  def build_edit_summary(changes_hash)
    change_count = changes_hash.keys.size
    change_types = changes_hash.keys.map do |field|
      case field
      when :summary
        'summary'
      when :description
        'description'
      when :priority
        'priority'
      when :status
        'status'
      when :severity
        'severity'
      when :labels
        'labels'
      when :assignees
        'assignees'
      else
        field.to_s.humanize.downcase
      end
    end

    if change_count == 1
      "Updated #{change_types.first}"
    else
      "Updated #{change_count} fields: #{change_types.join(', ')}"
    end
  end

  def send_edit_notifications(changes_hash)
    # Get all users who should be notified (current assignees + watchers)
    notify_users = @defect.users.pluck(:email)

    # Convert all values to plain strings for Sidekiq serialization
    json_safe_changes = convert_to_json_safe(changes_hash)

    # Determine notification priority based on change types
    high_priority_changes = %i[status priority assignees].any? { |field| json_safe_changes.key?(field) }

    if high_priority_changes
      # Send immediate high-priority notification (queued in background)
      change_types = []
      change_types << 'Status' if json_safe_changes.key?(:status)
      change_types << 'Priority' if json_safe_changes.key?(:priority)
      change_types << 'Assignees' if json_safe_changes.key?(:assignees)
      subject_text = "[URGENT] Defect #{@defect.defect_unique} - #{change_types.join(', ')} Updated by #{current_user.name}"

      notify_users.each do |email|
        user = User.find_by(email: email)
        Messaging::EmailSender.send_email(
          subject_text,
          to: [email],
          actor: current_user,
          priority: :important,
          type: 'defect_priority_update'
        ).use_template(
          view: 'user_mailer/defect_priority_update_email',
          assigns: { defect: @defect, actor: current_user, changes_hash: json_safe_changes }
        ).set_source('defect', @defect.id).set_party('user', user&.id).send(queue: true)
      end
    else
      # Send standard edit notification
      change_count = json_safe_changes.keys.size
      subject_text = "[Defect #{@defect.defect_unique}] #{change_count} update#{'s' if change_count > 1} by #{current_user.name}"

      notify_users.each do |email|
        user = User.find_by(email: email)
        Messaging::EmailSender.send_email(
          subject_text,
          to: [email],
          actor: current_user,
          priority: :normal,
          type: 'defect_edit_notification'
        ).use_template(
          view: 'user_mailer/defect_edit_notification_email',
          assigns: { defect: @defect, actor: current_user, changes_hash: json_safe_changes }
        ).set_source('defect', @defect.id).set_party('user', user&.id).send(queue: true)
      end
    end
  end

  # Convert SafeBuffer and other non-JSON types to plain strings
  def convert_to_json_safe(hash)
    hash.deep_transform_values do |value|
      case value
      when ActiveSupport::SafeBuffer
        value.to_str # Convert SafeBuffer to plain string
      when String
        value.to_s # Ensure it's a plain string
      else
        value # Keep other types as-is
      end
    end
  end

  # Normalize HTML content for semantic comparison
  # Converts HTML to plain text to detect actual content changes
  # This ignores formatting, whitespace, and HTML structure differences
  def normalize_html(html_string)
    return '' if html_string.blank?

    begin
      # Convert to string and add spaces around block-level tags to preserve word boundaries
      html = html_string.to_s

      # Add space around block-level tags so content doesn't merge when tags are removed
      html = html.gsub(%r{</(p|div|li|ul|ol|h1|h2|h3|h4|h5|h6|br)>}i, ' ')
      html = html.gsub(/<(p|div|li|ul|ol|h1|h2|h3|h4|h5|h6|br)[^>]*>/i, ' ')

      # Strip all HTML tags
      plain_text = ActionView::Base.full_sanitizer.sanitize(html)

      # Decode HTML entities
      plain_text = CGI.unescapeHTML(plain_text)

      # Normalize whitespace: collapse multiple spaces, remove newlines, trim
      plain_text.gsub(/\s+/, ' ')
        .strip
        .downcase
    rescue StandardError => e
      Rails.logger.error "Error normalizing HTML: #{e.message}"
      html_string.to_s.gsub(/\s+/, ' ').strip.downcase
    end
  end
end
