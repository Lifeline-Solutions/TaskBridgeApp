class DefectFilter < ApplicationRecord
  belongs_to :user
  belongs_to :product, optional: true

  # Audit associations
  belongs_to :created_by, class_name: 'User', foreign_key: 'created_by_id', optional: true
  belongs_to :modified_by, class_name: 'User', foreign_key: 'modified_by_id', optional: true
  belongs_to :deleted_by, class_name: 'User', foreign_key: 'deleted_by_id', optional: true

  scope :active, -> { where(deleted_on: nil, archive_status: false) }

  validates :name, presence: true, length: { maximum: 200 }
  validate :filters_must_be_hash

  # Whitelist of allowed keys that may be saved/applied (update when you add new filter inputs)
  ALLOWED_FILTER_KEYS = %w[
    client_name product_id query order start_date end_date priority user_id
    qa_module_id submodule_id banking_type_id label_ids status page
  ].freeze

  # Return sanitized filters (symbol/string indifferent)
  def sanitized_filters
    (filters || {}).with_indifferent_access.slice(*ALLOWED_FILTER_KEYS)
  end

  def sanitized_filters_string_keys
    sanitized_filters.deep_stringify_keys
  end

  private

  def filters_must_be_hash
    return if filters.is_a?(Hash)

    errors.add(:filters, 'must be a JSON object/hash')
  end
end
