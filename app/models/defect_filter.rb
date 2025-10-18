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
  attribute :chart_config, :jsonb, default: -> { {} }

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

  private

  def filters_must_be_hash
    return if filters.is_a?(Hash)

    errors.add(:filters, 'must be a JSON object/hash')
  end
end
