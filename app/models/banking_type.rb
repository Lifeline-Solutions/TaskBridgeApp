class BankingType < ApplicationRecord
  include Auditable
  include TrackableActivity
  include SoftDeletable

  # Many-to-many relationship with products
  has_and_belongs_to_many :products,
                          join_table: :banking_types_products

  # Legacy association - keep for backward compatibility during migration
  # belongs_to :product, optional: true

  has_many :defects, dependent: :nullify

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  # Scope to get banking types for a specific product (or multiple products)
  scope :for_product, lambda { |product_ids|
    left_joins(:products)
      .where('banking_types_products.product_id IN (:pids) OR banking_types.product_id IN (:pids)', pids: Array(product_ids))
      .distinct
      .order(:name)
  }

  # Scope to get banking types NOT yet assigned to a product
  scope :not_in_product, lambda { |product_id|
    where.not(id: left_joins(:products)
      .where('banking_types_products.product_id = :pid OR banking_types.product_id = :pid', pid: product_id)
      .select(:id))
      .order(:name)
  }

  # Scope for active (non-deleted) banking types
  scope :active, -> { where(deleted_on: nil, archive_status: false) }
end
