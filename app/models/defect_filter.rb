class DefectFilter < ApplicationRecord
  belongs_to :user
  belongs_to :product, optional: true

  # Audit associations
  belongs_to :created_by, class_name: 'User', foreign_key: 'created_by_id', optional: true
  belongs_to :modified_by, class_name: 'User', foreign_key: 'modified_by_id', optional: true
  belongs_to :deleted_by, class_name: 'User', foreign_key: 'deleted_by_id', optional: true

  scope :active, -> { where(deleted_on: nil, archive_status: false) }
  scope :defect_filters, -> { where(filter_type: 'defect') }
  scope :report_dashboards, -> { where(filter_type: 'report') }
  scope :dashboards, -> { where(is_dashboard: true) }

  validates :name, presence: true, length: { maximum: 200 }
  validates :filter_type, presence: true
  validate :filters_must_be_hash

  # Default values
  attribute :filters, :jsonb, default: -> { {} }
  attribute :filter_rules, :jsonb, default: -> { {} }
  attribute :chart_config, :jsonb, default: -> { {} }

  # Returns the active filter configuration (prefers new filter_rules over legacy filters)
  def active_rules
    filter_rules.present? ? filter_rules : filters
  end

  # Check if using new condition-based format
  def uses_condition_format?
    filter_rules.present? && (filter_rules['conditions'] || filter_rules[:conditions])
  end

  # Apply this filter to a base relation
  def apply_to(base_relation)
    DefectQueryBuilder.new(base_relation).apply_rules(active_rules)
  end

  # Convert legacy filters to new format (for migration purposes)
  def migrate_to_filter_rules!
    return if filter_rules.present? || filters.blank?
    
    self.filter_rules = FilterAugmentor.legacy_to_new_format(filters)
    save
  end

  # Whitelist of allowed keys that may be saved/applied (update when you add new filter inputs)
  ALLOWED_FILTER_KEYS = %w[
    client_name product_id query order start_date end_date priority user_id
    qa_module_id submodule_id banking_type_id label_ids status page
    filter_open select_all_module select_all_submodule
  ].freeze

  # Report-specific allowed keys
  REPORT_ALLOWED_FILTER_KEYS = %w[
    metrics severities reporters statuses assignees modules submodules
    ageing_type start_date end_date product_id
  ].freeze

  # Enum for filter types
  attribute :filter_type, :string
  enum filter_type: {
    defect: 'defect',
    report: 'report'
  }

  # Return sanitized filters based on filter type
  def sanitized_filters
    return sanitized_report_filters if report_filter?

    (filters || {}).with_indifferent_access.slice(*ALLOWED_FILTER_KEYS)
  end

  def sanitized_filters_string_keys
    sanitized_filters.deep_stringify_keys
  end

  # Return sanitized report filters
  def sanitized_report_filters
    return {} unless report_filter?

    filters_hash = (filters || {}).with_indifferent_access

    # Handle both string and symbol keys, and parse JSON strings if needed
    report_filters = {}

    REPORT_ALLOWED_FILTER_KEYS.each do |key|
      value = filters_hash[key]

      # Parse JSON strings back to arrays/objects for report parameters
      if value.is_a?(String) && (key.end_with?('s') || key == 'metrics')
        begin
          value = JSON.parse(value)
        rescue JSON::ParserError
          # Keep as string if parsing fails
        end
      end

      report_filters[key] = value unless value.blank?
    end

    report_filters.with_indifferent_access
  end

  def self.defect_filter_params
    %w[status priority user_id qa_module_id submodule_id banking_type_id label_ids order start_date end_date query]
  end

  def self.report_filter_params
    %w[metrics severities reporters statuses assignees modules submodules ageing_type start_date end_date]
  end

  def defect_filter?
    filter_type == 'defect'
  end

  def report_filter?
    filter_type == 'report'
  end

  # Generate proper report parameters for URL
  def to_report_params
    return {} unless report_filter?

    params = sanitized_report_filters

    # Ensure array parameters are properly formatted for URLs
    %w[metrics severities reporters statuses assignees modules submodules].each do |array_field|
      if params[array_field].is_a?(Array)
        # Rails will automatically handle array parameters in URLs
        # This will create params like: metrics[]=severity&metrics[]=reporter
      end
    end

    params
  end

  # Get product names from filters
  def product_names
    # Get product_id from filters (works for both report and defect filters)
    product_ids = sanitized_filters['product_id']

    # Handle various formats: string, array, or single value
    product_ids = if product_ids.is_a?(String)
                    product_ids.split(',').map(&:strip)
                  else
                    Array(product_ids)
                  end.reject(&:blank?)

    return 'All Projects' if product_ids.empty?

    # Fetch product names
    products = Product.where(id: product_ids).includes(:client, :groupwares)

    if products.empty?
      # Fallback to the single product association if filters don't have product_id
      product&.document_name || 'All Projects'
    elsif products.count == 1
      # Single product - show full name
      products.first.document_name
    else
      # Multiple products - show count
      "#{products.count} projects"
    end
  end

  private

  def filters_must_be_hash
    return if filters.is_a?(Hash)

    errors.add(:filters, 'must be a JSON object/hash')
  end
end
