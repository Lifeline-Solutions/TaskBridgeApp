# app/models/default_defect_assignee.rb
class DefaultDefectAssignee < ApplicationRecord
  belongs_to :user

  validates :user_id, presence: true, uniqueness: true

  # Safe accessor helpers for convenience
  def self.instance
    # Return first non-deleted instance (your app may already add default scope)
    first
  end

  def self.user
    instance&.user
  end

  def self.user_id
    instance&.user_id
  end

  # NOTE: creation / update / soft delete should be handled in controller
  # so audit_on_create / audit_on_update / audit_soft_delete can be called there.
end
