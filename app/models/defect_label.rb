class DefectLabel < ApplicationRecord
  include SoftDeletable

  belongs_to :defect
  belongs_to :label

  # Don't validate defect_id presence: association sets it after parent persists
  validates :label_id, presence: true
end
