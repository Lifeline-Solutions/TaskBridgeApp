class Product < ApplicationRecord
  belongs_to :user
  has_and_belongs_to_many :softwares
  has_and_belongs_to_many :groupwares

  # Milestones associations
  has_many :milestones, dependent: :destroy
  accepts_nested_attributes_for :milestones, allow_destroy: true

  belongs_to :client
  has_many :boards, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :documents, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true
  has_one_attached :image
  has_many :defects, dependent: :nullify
  before_create :set_default_status

  has_rich_text :content

  resourcify
  has_many :users, through: :roles, class_name: 'User', source: :users
  has_many :creators, -> { where(roles: { name: :admin }) }, class_name: 'User', through: :roles, source: :users

  has_many :addusers
  has_many :users, through: :addusers, dependent: :destroy
  has_and_belongs_to_many :statuses, dependent: :destroy

  scope :with_quality_assurance_status, lambda {
    joins(:statuses).where(statuses: { name: 'Quality Assurance' }).distinct
  }

  validate :end_date_after_start_date

  def added_to?(user)
    users.include?(user)
  end

  def craftsilicon_users
    User.where('email LIKE ANY (array[?, ?, ?]) AND active = ?', '%@craftsilicon.com', '%@craftsilicon.co.tz', '%@little.africa', true)
  end

  def set_default_status
    status = Status.find_by(name: 'Initiation')
    statuses << status if status
  end

  private

  def content_length_within_limit
    return unless content.to_plain_text.length > 800

    errors.add(:content, 'must be less than or equal to 800 characters')
  end

  def end_date_after_start_date
    return unless end_date.present? && start_date.present? && end_date < start_date

    errors.add(:end_date, 'End Date must be greater than Start Date')
  end

  def count
    # Count the number of projects by all users
    # and display it
    Product.count
  end
end
