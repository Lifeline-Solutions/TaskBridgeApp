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
  scope :for_product, ->(product_ids) {
    joins(:products).where(products: { id: Array(product_ids) }).distinct.order(:name)
  }
  
  # Scope to get banking types NOT yet assigned to a product
  scope :not_in_product, ->(product_id) {
    where.not(id: joins(:products).where(products: { id: product_id }).select(:id)).order(:name)
  }
  
  # Scope for active (non-deleted) banking types
  scope :active, -> { where(deleted_on: nil, archive_status: false) }
end
