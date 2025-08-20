class Defect < ApplicationRecord
  has_rich_text :content
  has_many_attached :images
  has_many_attached :videos
  has_many_attached :attachments
  belongs_to :qa_module, class_name: 'QaModule'
  belongs_to :submodule, class_name: 'QaModule', optional: true
  belongs_to :banking_type
  belongs_to :product
  belongs_to :status
  belongs_to :creator, class_name: 'User'
  has_and_belongs_to_many :users, join_table: :defects_users

  resourcify
  has_many :users, through: :roles, class_name: 'User', source: :users
  has_many :creators, -> { where(roles: { name: :admin }) }, class_name: 'User', through: :roles, source: :users
  has_many :editors, lambda {
    where(roles: { name: ['admin', 'project manager'] })
  }, class_name: 'User', through: :roles, source: :users

  has_and_belongs_to_many :users

  def assigned_to?(user)
    users.include?(user)
  end

  def craftsilicon_users
    User.where('email LIKE ANY (array[?, ?, ?]) AND active = ?', '%@craftsilicon.com', '%@craftsilicon.co.tz', '%@little.africa', true)
  end

  before_validation :set_default_status, on: :create

  private

  def set_default_status
    self.status ||= Status.find_by(name: 'TO DO')
  end
end
