class DefectFiltersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_defect_filter, only: %i[edit update destroy]

  def index
    @defect_filters = current_user.defect_filters.active.includes(:product).order(:name)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          defect_filters: @defect_filters.map do |f|
            {
              id: f.id,
              name: f.name,
              filters: f.filters
            }
          end
        }
      end
    end
  end

  def edit
    # Determine which product(s) are relevant to this filter
    filter_product_ids = Array(@defect_filter.product_id).compact
    saved_filter_product_ids = Array(@defect_filter.filters['product_id']).compact
    relevant_product_ids = (filter_product_ids + saved_filter_product_ids).uniq.compact

    # Load products scoped to this filter
    @qa_products = if relevant_product_ids.any?
                     # Show only the specific product(s) associated with this filter
                     Product
                       .where(id: relevant_product_ids)
                       .includes(:client, :groupwares, :statuses)
                       .where('products.deleted_on IS NULL')
                       .order('products.document_name ASC')
                   else
                     # Fallback: show all QA products if no specific product is set
                     Product
                       .includes(:client, :groupwares, :statuses)
                       .joins(:statuses)
                       .where(statuses: { name: ['Pre Quality Assurance', 'End Of Quality Assurance'] })
                       .where('products.deleted_on IS NULL')
                       .distinct
                       .order('products.document_name ASC')
                   end

    # Scope ALL data strictly to defects within the relevant products
    if relevant_product_ids.any?
      # Load assignees - users who are assigned to defects in these products (via defects_users join table)
      @users = User
        .joins('INNER JOIN defects_users ON users.id = defects_users.user_id')
        .joins('INNER JOIN defects ON defects.id = defects_users.defect_id')
        .where(defects: { product_id: relevant_product_ids })
        .where('defects_users.deleted_on IS NULL')
        .where(active: true)
        .distinct
        .order(:first_name, :last_name)

      # Load reporters - users who have created defects in these products
      @reporters = User
        .joins('INNER JOIN defects ON users.id = defects.created_by')
        .where(defects: { product_id: relevant_product_ids })
        .where(active: true)
        .distinct
        .order(:first_name, :last_name)

      # Load modules - only modules used in defects for these products
      @modules = QaModule
        .joins('INNER JOIN defects ON qa_modules.id = defects.qa_module_id OR qa_modules.id = defects.submodule_id')
        .where(defects: { product_id: relevant_product_ids })
        .includes(:children, :parent)
        .distinct
        .order(:name)

      # Load banking types - only banking types used in defects for these products
      @banking_types = BankingType
        .joins('INNER JOIN defects ON banking_types.id = defects.banking_type_id')
        .where(defects: { product_id: relevant_product_ids })
        .where(archive_status: false)
        .distinct
        .order(:name)

      # Load statuses - only statuses used in defects for these products (via defect_statuses join table)
      @statuses = Status
        .joins('INNER JOIN defect_statuses ON statuses.id = defect_statuses.status_id')
        .joins('INNER JOIN defects ON defects.id = defect_statuses.defect_id')
        .where(defects: { product_id: relevant_product_ids })
        .where('defect_statuses.deleted_on IS NULL')
        .distinct
        .order(:name)

      # Load labels - only labels used in defects for these products
      @labels = Label
        .joins(:defects)
        .where(defects: { product_id: relevant_product_ids })
        .where('labels.deleted_on IS NULL')
        .distinct
        .order(:name)
    else
      # Fallback: load all active data (when no specific product is selected)
      @users = User.where(active: true).order(:first_name, :last_name)
      @reporters = User.where(active: true).order(:first_name, :last_name)
      @modules = QaModule.includes(:children, :parent).distinct.order(:name)
      @banking_types = BankingType.where(archive_status: false).order(:name)
      @statuses = Status.distinct.order(:name)
      @labels = Label.where('deleted_on IS NULL').distinct.order(:name)
    end

    # Parse existing filter criteria for the form
    @current_filters = @defect_filter.sanitized_filters_string_keys

    # Ensure product_id is included in current_filters for proper pre-selection
    if @defect_filter.product_id.present? && @current_filters['product_id'].blank?
      @current_filters['product_id'] = [@defect_filter.product_id.to_s]
    elsif @current_filters['product_id'].present?
      # Normalize to array of strings
      @current_filters['product_id'] = Array(@current_filters['product_id']).map(&:to_s)
    end

    # Normalize all array-based filter values to strings for consistent comparison
    %w[user_id reporter_id qa_module_id submodule_id label_ids status priority banking_type_id].each do |key|
      @current_filters[key] = Array(@current_filters[key]).map(&:to_s) if @current_filters[key].present?
    end
  end

  def create
    # 1. Parse raw filter parameters safely from nested or top-level params
    raw_filters = parse_filters_param(
      params.dig(:defect_filter, :filters) || params[:filters]
    )

    # 2. Sanitize and normalize filter keys
    permitted_filters = permit_filter_keys(raw_filters)

    # 3. Normalize product_id (handle string, array, or nil)
    product_param = params.dig(:defect_filter, :product_id) || params[:product_id]
    normalized_product_id =
      case product_param
      when Array
        product_param.first
      when String
        product_param.split(/[ ,]+/).reject(&:blank?).first
      end

    # 4. Build the defect filter record
    @defect_filter = current_user.defect_filters.build(
      name: params.dig(:defect_filter, :name) || params[:name] || 'Unnamed filter',
      product_id: normalized_product_id,
      filters: permitted_filters
    )

    # 5. Audit metadata
    @defect_filter.created_by = current_user
    @defect_filter.modified_by = current_user
    @defect_filter.archive_status = false

    # 6. Save and redirect appropriately
    if @defect_filter.save
      redirect_back(
        fallback_location: index_show_defect_index_path(
          product_id: @defect_filter.product_id,
          **@defect_filter.filters.symbolize_keys
        ),
        notice: 'Filter saved successfully.'
      )
    else
      redirect_back(
        fallback_location: index_show_defect_index_path(
          product_id: params[:product_id]
        ),
        alert: @defect_filter.errors.full_messages.to_sentence
      )
    end
  end

  def update
    # Collect filter parameters from the form
    # The form submits filter fields directly, not nested under defect_filter[filters]
    raw_filters = {
      'product_id' => params[:product_id],
      'status' => params[:status],
      'priority' => params[:priority],
      'user_id' => params[:user_id],
      'reporter_id' => params[:reporter_id],
      'qa_module_id' => params[:qa_module_id],
      'submodule_id' => params[:submodule_id],
      'label_ids' => params[:label_ids],
      'banking_type_id' => params[:banking_type_id],
      'query' => params[:query],
      'start_date' => params[:start_date],
      'end_date' => params[:end_date],
      'filter_open' => params[:filter_open]
    }.compact

    # Update filter attributes
    @defect_filter.name = params.dig(:defect_filter, :name) if params.dig(:defect_filter, :name).present?
    @defect_filter.filters = permit_filter_keys(raw_filters)
    @defect_filter.modified_by = current_user
    @defect_filter.updated_at = Time.current

    if @defect_filter.save
      redirect_to defect_filters_path, notice: 'Filter updated successfully!'
    else
      @qa_products = Product.qa_projects.active
      @users = User.where(active: true).order(:first_name, :last_name)
      @modules = QaModule.includes(:children, :parent).distinct.order(:name)
      @statuses = Status.distinct.order(:name)
      @labels = Label.distinct.order(:name)
      @banking_types = BankingType.active.order(:name)
      @current_filters = @defect_filter.sanitized_filters_string_keys

      render :edit, status: :unprocessable_entity
    end
  end

  # Soft-delete (audit)
  def destroy
    @defect_filter.update(deleted_on: Time.current, deleted_by: current_user, archive_status: true)
    redirect_back fallback_location: defect_filters_path, notice: 'Filter deleted'
  end

  private

  def set_defect_filter
    @defect_filter = current_user.defect_filters.find(params[:id])
  end

  def parse_filters_param(filters_param)
    case filters_param
    when String
      begin
        JSON.parse(filters_param)
      rescue JSON::ParserError
        # If it's not JSON, try to parse as URL parameters
        parse_url_params(filters_param)
      end
    when ActionController::Parameters
      filters_param.to_unsafe_h
    when Hash
      filters_param
    else
      {}
    end
  end

  def parse_url_params(url_params)
    # Handle URL-encoded parameters like product_id%5B%5D=xxx
    parsed = {}
    CGI.parse(url_params).each do |key, value|
      clean_key = key.gsub('[]', '')
      parsed[clean_key] = value.size == 1 ? value.first : value
    end
    parsed
  end

  def permit_filter_keys(raw_hash)
    raw = raw_hash.to_h.with_indifferent_access.slice(*DefectFilter::ALLOWED_FILTER_KEYS)

    # Normalize array parameters
    array_keys = %w[product_id user_id reporter_id qa_module_id submodule_id label_ids status priority banking_type_id]
    array_keys.each do |key|
      raw[key] = Array(raw_hash[key]).reject(&:blank?) if raw_hash.key?(key)
    end

    # Handle boolean/string parameters
    raw['filter_open'] = raw_hash['filter_open'] if raw_hash.key?('filter_open')
    raw['select_all_module'] = raw_hash['select_all_module'] if raw_hash.key?('select_all_module')
    raw['select_all_submodule'] = raw_hash['select_all_submodule'] if raw_hash.key?('select_all_submodule')
    raw['select_all_reporter'] = raw_hash['select_all_reporter'] if raw_hash.key?('select_all_reporter')

    raw
  end
end
