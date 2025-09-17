class TicketFeedback < ApplicationRecord
  # Associations
  belongs_to :ticket
  belongs_to :creator, class_name: 'User', foreign_key: :creator_id

  has_rich_text :comment

  validates :rating, presence: true, inclusion: { in: 1..5 }
  validates :captured_at, presence: true

  scope :visible, -> { where(archive_status: false) }
  scope :recent_first, -> { order(captured_at: :desc) }
end
