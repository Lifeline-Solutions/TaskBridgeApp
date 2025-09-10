class DefectFailureReport < ApplicationRecord
  # Associations
  belongs_to :defect

  has_rich_text :reason

  # Validations
  validates :retest_number, presence: true
  validates :captured_at, presence: true
end
