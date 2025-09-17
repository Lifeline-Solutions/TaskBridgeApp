class DefectFailureReport < ApplicationRecord
  # Associations
  belongs_to :defect
  belongs_to :creator, class_name: 'User', foreign_key: :created_by_id

  has_rich_text :reason

  # Validations
  validates :retest_number, presence: true
  validates :captured_at, presence: true

  scope :visible, -> { where(archive_status: false, deleted_on: nil) }
end
