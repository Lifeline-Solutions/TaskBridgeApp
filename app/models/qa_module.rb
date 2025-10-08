class QaModule < ApplicationRecord
  belongs_to :product
  belongs_to :parent, class_name: 'QaModule', optional: true
  has_many :children, class_name: 'QaModule', foreign_key: 'parent_id', dependent: :destroy
  has_many :submodules, class_name: 'QaModule', foreign_key: 'parent_id', dependent: :destroy
  has_many :defects, dependent: :nullify

  validates :name, presence: true

  # Scopes
  scope :modules, -> { where(parent_id: nil) }
  scope :submodules, -> { where.not(parent_id: nil) }

  # Instance methods
  def module?
    parent_id.nil?
  end
  
  def submodule?
    parent_id.present?
  end
end
