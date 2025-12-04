class DefectFiltersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_defect_filter, only: %i[edit update destroy]

  def index
    @defect_filters = current_user.defect_filters.active.includes(:product).order(:name)
  end

  def edit
    # Load all necessary data for the edit form
    @qa_products = Product
      .includes(:client, :groupwares, :statuses)
      .joins(:statuses)
      .where(statuses: { name: ['Pre Quality Assurance', 'End Of Quality Assurance'] })
      .where('products.deleted_on IS NULL')
      .distinct
      .order('products.document_name ASC')

    # Load users, modules, statuses, and labels for filter options
    @users = User.where(active: true).order(:first_name, :last_name)
    @modules = QaModule.includes(:children, :parent).distinct.order(:module_name)
    @statuses = Status.distinct.order(:name)
    @labels = Label.includes(:labellable).distinct.order(:name)

    # Parse existing filter criteria for the form
    @current_filters = @defect_filter.sanitized_filters_string_keys
  end

  def create
    # 1. Parse raw filter parameters safely from nested or top-level params
    raw_filters = parse_filters_param(
      params.dig(:defect_filter, :filters) || params[:filters]
    )

    # 2. Sanitize and normalize filter keys
    permitted_filters = permit_filter_keys(raw_filters)

    # 3️. Normalize product_id (handle string, array, or nil)
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
    # Check if this is a filter criteria update (from edit form) or just a name update
    if params[:product_id] || params[:status] || params[:priority] || params[:user_id] ||
       params[:reporter_id] || params[:qa_module_id] || params[:submodule_id] ||
       params[:label_ids] || params[:query] || params[:start_date] || params[:end_date] ||
       params[:filter_open]

      # This is a full filter criteria update from the edit form
      raw_filters = {
        'product_id' => params[:product_id],
        'status' => params[:status],
        'priority' => params[:priority],
        'user_id' => params[:user_id],
        'reporter_id' => params[:reporter_id],
        'qa_module_id' => params[:qa_module_id],
        'submodule_id' => params[:submodule_id],
        'label_ids' => params[:label_ids],
        'query' => params[:query],
        'start_date' => params[:start_date],
        'end_date' => params[:end_date],
        'filter_open' => params[:filter_open]
      }.reject { |k, v| v.blank? }

      @defect_filter.filters = permit_filter_keys(raw_filters)

      # Handle product_id association
      product_param = params[:product_id]
      normalized_product_id =
        case product_param
        when Array
          product_param.first
        when String
          product_param.split(/[ ,]+/).reject(&:blank?).first
        end
      @defect_filter.product_id = normalized_product_id

    elsif params.dig(:defect_filter, :filters).present?
      # Legacy filter update (JSON format)
      raw_filters = parse_filters_param(params.dig(:defect_filter, :filters))
      @defect_filter.filters = permit_filter_keys(raw_filters)
    end

    # Update name if provided
    @defect_filter.name = params.dig(:defect_filter, :name) if params.dig(:defect_filter, :name).present?
    @defect_filter.modified_by = current_user

    if @defect_filter.save
      redirect_to defect_filters_path, notice: 'Filter updated successfully'
    else
      redirect_back fallback_location: defect_filters_path, alert: @defect_filter.errors.full_messages.to_sentence
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
    array_keys = %w[product_id user_id reporter_id qa_module_id submodule_id label_ids status]
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
