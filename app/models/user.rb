class User < ApplicationRecord
  attr_accessor :skip_invitation

  rolify
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :invitable, :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :confirmable, :lockable, :timeoutable, :trackable
  # To ensure that a user has at least one role
  has_one_attached :profile_picture
  # To ensure that a user has at least one role
  has_many :projects, foreign_key: :user_id, class_name: 'Project', dependent: :nullify
  has_many :tickets, foreign_key: :user_id, class_name: 'Ticket', dependent: :nullify
  has_many :issues, foreign_key: :user_id, class_name: 'Issue', dependent: :nullify
  has_many :messages, foreign_key: :user_id, class_name: 'Message', dependent: :nullify
  has_many :comments, foreign_key: :user_id, class_name: 'Comment', dependent: :nullify
  # Products to Projects
  has_many :products, foreign_key: :user_id, class_name: 'Product', dependent: :nullify
  has_many :boards, foreign_key: :user_id, class_name: 'Board', dependent: :nullify
  has_many :tasks, foreign_key: :user_id, class_name: 'Task', dependent: :nullify

  # Defect a.k.a. Quality Assurance
  has_many :defects, foreign_key: :user_id, class_name: 'Defect', dependent: :nullify

  # To ensure that a user has at least one role
  has_many :projects, through: :roles, source: :resource, source_type: :Project
  has_many :tickets, through: :roles, source: :resource, source_type: :Ticket
  has_many :issues, through: :roles, source: :resource, source_type: :Issue
  has_many :comments, through: :roles, source: :resource, source_type: :Comment
  has_many :messages, through: :roles, source: :resource, source_type: :Message

  # Products to Projects
  has_many :products, through: :roles, source: :resource, source_type: :Product
  has_many :boards, through: :roles, source: :resource, source_type: :Board
  has_many :tasks, through: :roles, source: :resource, source_type: :Task
  has_many :defects, through: :roles, source: :resource, source_type: :Defect

  has_many :assignees
  has_many :projects, through: :assignees
  has_many :notifications, dependent: :destroy

  # Associations for the commonly accessed clients in the ceasefire report
  has_many :commonly_selected_clients, dependent: :destroy
  has_many :common_clients, through: :commonly_selected_clients, source: :client

  after_initialize :set_default_profile_completed, if: :new_record?
  validate :email_domain_must_be_certified, on: %i[create invitation_create skip_invitation]

  # To show which user invited a user

  has_many :invitees, class_name: 'User', foreign_key: :invited_by_id

  # To ensure that a user has at least one role
  before_create :assign_default_role
  # To ensure that a user has at least one role
  validate :must_have_a_role, on: :update

  # Tagging the user to the ticket
  has_many :taggings
  has_many :tickets, through: :taggings

  has_many :addusers
  has_many :products, through: :addusers

  has_many :add_tasks
  has_many :tasks, through: :add_tasks

  has_many :states
  has_many :tasks, through: :states

  has_many :add_bugs
  has_many :bugs, through: :add_bugs

  has_many :defect_messages, dependent: :destroy

  has_many :softwares
  belongs_to :client, optional: true
  belongs_to :location, optional: true
  has_and_belongs_to_many :teams
  has_and_belongs_to_many :messages
  has_many :authored_messages,
           class_name: 'Message',
           foreign_key: :user_id,
           inverse_of: :author,
           dependent: :nullify
  has_and_belongs_to_many :tagged_messages,
                          class_name: 'Message',
                          join_table: 'messages_users'

  has_and_belongs_to_many :defects, join_table: :defects_users

  def assign_default_role
    return if invited_by_id.present?

    add_role(:client) if roles.blank?
  end

  # To have a list of user who only have a specific role
  def self.with_agent_project_manager_role
    joins(:roles).where(roles: { name: 'project manager' }, first_login: true, active: true)
  end

  def self.with_agent_role
    joins(:roles).where(roles: { name: ['agent', 'client', 'project manager', 'admin'] }, first_login: true, active: true)
  end

  def self.with_assigned_role
    joins(:roles).where(roles: { name: ['agent', 'project manager', 'admin', 'observer'] }, first_login: true, active: true)
  end

  def self.with_client_role
    joins(:roles).where(roles: { name: ['client'] }, first_login: true, active: true)
  end

  def tagging_to?(user)
    # if project has user added show the list of users
    # who have been added to the project
    return false unless project.users.include?(user)

    users.include?(user)
  end

  def client?
    has_role?(:client)
  end

  # To ensure either the first name or last name is present and they appear in the initials
  def name_initials
    if first_name.present? && last_name.present?
      "#{first_name[0]}#{last_name[0]}"
    elsif first_name.present?
      first_name[0]
    elsif last_name.present?
      last_name[0]
    else
      blank?
    end
  end

  def name
    "#{first_name} #{last_name}"
  end

  def set_default_profile_completed
    self.first_login ||= false
  end

  def toggle_boolean(attribute)
    update(attribute => !self[attribute])
  end

  def all_projects_for_the_current_user_count
    projects.distinct.count(:id)
  end

  def all_open_tickets_for_the_current_user_count
    tickets.joins(:statuses).where.not(statuses: { name: %w[Closed Resolved Declined Approved] }).distinct.count(:id)
  end

  private

  def email_domain_must_be_certified
    allowed_domains = %w[craftsilicon.com little.africa craftsilicon.co.tz]
    domain = email.split('@').last
    return if allowed_domains.include?(domain)

    errors.add(:email, 'must be from a certified domain (craftsilicon.com or little.africa)')
  end

  def must_have_a_role
    return if roles.any?

    errors.add(:roles, 'must have at least one role')
  end
end
