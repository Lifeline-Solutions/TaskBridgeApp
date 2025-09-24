class DefectLink < ApplicationRecord
  include SoftDeletable

  belongs_to :source_defect, class_name: 'Defect'
  belongs_to :target_defect, class_name: 'Defect'

  validates :link_type, presence: true, inclusion: { in: %w[blocks blocked_by] }
  validates :source_defect_id, uniqueness: { scope: %i[target_defect_id link_type] }

  # Prevent self-linking
  validate :cannot_link_to_self

  # Define link types
  BLOCKS = 'blocks'.freeze
  BLOCKED_BY = 'blocked_by'.freeze

  scope :blocks_links, -> { where(link_type: BLOCKS) }
  scope :blocked_by_links, -> { where(link_type: BLOCKED_BY) }

  private

  def cannot_link_to_self
    return unless source_defect_id == target_defect_id

    errors.add(:target_defect_id, 'cannot link defect to itself')
  end
end
