# frozen_string_literal: true

class Dashboard < ApplicationRecord
  # Associations
  belongs_to :user
  has_many :widgets, dependent: :destroy
  
  # Audit associations
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :modified_by, class_name: 'User', optional: true
  belongs_to :deleted_by, class_name: 'User', optional: true
  
  # Scopes
  scope :active, -> { where(deleted_on: nil, archive_status: false) }
  scope :for_user, ->(user) { where(user: user) }
  scope :defaults, -> { where(is_default: true) }
  
  # Validations
  validates :name, presence: true, length: { maximum: 200 }
  validates :columns, presence: true, inclusion: { in: 1..4 }
  validates :user, presence: true
  
  # Ensure only one default dashboard per user
  validates :is_default, uniqueness: { scope: :user_id, message: "only one default dashboard allowed per user" }, if: :is_default?
  
  # Default values
  attribute :columns, :integer, default: 3
  attribute :is_default, :boolean, default: false
  attribute :archive_status, :boolean, default: false
  
  # Callbacks
  before_save :set_created_by, if: :new_record?
  before_save :set_modified_by
  
  # Class methods
  def self.find_or_create_default_for(user)
    user.dashboards.active.defaults.first_or_create(
      name: "My Dashboard",
      description: "Default dashboard",
      columns: 3,
      is_default: true,
      created_by: user
    )
  end
  
  # Instance methods
  def soft_delete!(deleted_by_user)
    update!(
      deleted_on: Time.current,
      deleted_by: deleted_by_user,
      modified_by: deleted_by_user
    )
  end
  
  def restore!
    update!(deleted_on: nil, deleted_by: nil)
  end
  
  def archive!(archived_by_user)
    update!(
      archive_status: true,
      modified_by: archived_by_user
    )
  end
  
  def unarchive!
    update!(archive_status: false)
  end
  
  def active?
    deleted_on.nil? && !archive_status
  end
  
  private
  
  def set_created_by
    self.created_by ||= user
  end
  
  def set_modified_by
    self.modified_by ||= user
  end
end
