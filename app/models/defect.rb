class Defect < ApplicationRecord
  has_rich_text :content
  has_many_attached :images
  has_many_attached :videos

  resourcify
  has_many :users, through: :roles, class_name: 'User', source: :users
  has_many :creators, -> { where(roles: { name: :admin }) }, class_name: 'User', through: :roles, source: :users
  has_many :editors, lambda {
    where(roles: { name: ['admin', 'project manager'] })
  }, class_name: 'User', through: :roles, source: :users

  # has_and_belongs_to_many :users, join_table: :defects_users

  belongs_to :product
  has_many :bugs, dependent: :destroy
  has_and_belongs_to_many :users

  def assigned_to?(user)
    users.include?(user)
  end

  def craftsilicon_users
    User.where('email LIKE ANY (array[?, ?, ?]) AND active = ?', '%@craftsilicon.com', '%@craftsilicon.co.tz', '%@little.africa', true)
  end
end