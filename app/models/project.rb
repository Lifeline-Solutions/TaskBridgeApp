class Project < ApplicationRecord
  belongs_to :user
  has_and_belongs_to_many :softwares
  has_and_belongs_to_many :groupwares
  belongs_to :client, optional: true
  has_one_attached :image

  has_many :tickets, dependent: :destroy
  has_many :issues, foreign_key: :project_id, class_name: 'Issue', dependent: :destroy
  has_many :comments, foreign_key: :project_id, class_name: 'Comment', dependent: :destroy

  has_rich_text :content

  resourcify
  has_many :users, through: :roles, class_name: 'User', source: :users
  has_many :creators, -> { where(roles: { name: :admin }) }, class_name: 'User', through: :roles, source: :users
  has_many :editors, lambda {
    where(roles: { name: ['admin', 'project manager'] })
  }, class_name: 'User', through: :roles, source: :users

  # Assingnee
  has_many :assignees
  has_many :users, through: :assignees, dependent: :destroy
  has_many :qa_modules, dependent: :destroy

  validates :title, presence: true, uniqueness: true

  validate :content_length_within_limit

  def assigned_to?(user)
    users.include?(user)
  end

  def users_with_same_client
    User.where(client_id: client_id, active: true)
  end

  def craftsilicon_users
    User.where('email LIKE ANY (array[?, ?, ?]) AND active = ?', '%@craftsilicon.com', '%@craftsilicon.co.tz', '%@little.africa', true)
  end
  # To have pick a list of users who have role agent only on a dropdown list at the view to assign a project

  private

  def content_length_within_limit
    return unless content.to_plain_text.length > 800

    errors.add(:content, 'must be less than or equal to 800 characters')
  end

  def name
    # Pick name name from the user_id assigned
    # to the project
    user.name
  end

  def count
    # Count the number of projects by all users
    # and display it
    Project.count
  end
end
