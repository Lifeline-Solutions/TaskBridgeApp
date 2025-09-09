class QaModule < ApplicationRecord
  belongs_to :product
  belongs_to :parent, class_name: 'QaModule', optional: true
  has_many :submodules, class_name: 'QaModule', foreign_key: 'parent_id', dependent: :destroy
  has_many :defects, dependent: :nullify

  validates :name, presence: true
end
