class SystemActivity < ApplicationRecord
  SYSTEM_USER_ID = 'c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da'.freeze

  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :causer, polymorphic: true, optional: true

  validates :event, presence: true

  # Ensure audit fields default to system user
  before_validation :ensure_sys_user_audit

  private

  def ensure_sys_user_audit
    self.created_by ||= SYSTEM_USER_ID
    self.modified_by ||= SYSTEM_USER_ID
  end
end
