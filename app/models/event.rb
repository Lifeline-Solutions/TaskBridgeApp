class Event < ApplicationRecord
  belongs_to :ticket
  belongs_to :user, optional: true
  belongs_to :assigned_user, class_name: 'User', optional: true

  before_validation :set_system_user_if_nil

  validates :ticket_id, :user_id, presence: true

  private

  def set_system_user_if_nil
    # If no user is provided (e.g., from a background job), use the system user
    if user_id.blank?
      system_user = User.find_by(id: SystemActivity::SYSTEM_USER_ID) ||
                    User.find_by(email: 'system@taskbridge.local') ||
                    User.first
      self.user_id = system_user.id if system_user.present?
    end
  end
end
