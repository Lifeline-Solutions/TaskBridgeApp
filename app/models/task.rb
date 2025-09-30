class Task < ApplicationRecord
  belongs_to :user
  belongs_to :product
  has_one_attached :image
  has_one_attached :file
  has_many :messages, dependent: :destroy
  before_create :set_default_state
  after_create :task_unique_id
  after_update :task_unique_id, if: :unique_task_id_missing?

  belongs_to :prerequisite_task, class_name: 'Task', foreign_key: 'tasks_id', optional: true
  resourcify

  has_many :role_users, through: :roles, class_name: 'User', source: :user
  has_many :creators, -> { where(roles: { name: :creator }) }, class_name: 'User', through: :roles, source: :user

  validate :end_date_after_start_date
  validate :image_must_be_an_image
  validate :file_must_be_a_file
  validate :prerequisite_task_must_be_resolved, on: :update

  has_many :add_tasks
  has_many :users, through: :add_tasks, dependent: :destroy
  has_and_belongs_to_many :statuses, dependent: :destroy
  has_many :bugs
  has_rich_text :description
  scope :for_product, ->(product_id) { where(product_id: product_id) }

  def set_default_state
    status = Status.find_by(name: 'TO DO')
    statuses << status if status
  end

  def self.prerequisite_tasks(product_id, exclude_task_id = nil)
    resolved_status = Status.find_by(name: 'Resolved')
    tasks = if resolved_status
              joins(:statuses)
                .where(product_id: product_id)
                .where.not(statuses: { id: resolved_status.id })
                .distinct
            else
              where(product_id: product_id)
            end

    # Exclude the current task to prevent self-reference
    tasks = tasks.where.not(id: exclude_task_id) if exclude_task_id.present?
    tasks
  end

  # if task has a prerequisite task, the prerequisite task should have status resolved
  # if not it one should not be able to update status
  def prerequisite_task_must_be_resolved
    return unless prerequisite_task.present?

    # Allow updates that are just setting unique_task_id or timestamps
    return if changes.blank? # No changes means we're probably in a callback

    # Skip validation for non-critical updates
    critical_attributes = %w[name description start_date end_date priority]
    critical_changes = changes.keys & critical_attributes

    # If we're only updating non-critical attributes, allow it
    return if critical_changes.empty?

    # Only validate when there are actual critical changes AND prerequisite isn't resolved
    return if prerequisite_task.statuses.exists?(name: 'Resolved')

    errors.add(:base, "Prerequisite task '#{prerequisite_task.unique_task_id || prerequisite_task.id}' must be resolved before updating this task.")
  end

  def task_unique_id
    return if unique_task_id.present? # Don't regenerate if already exists

    initials =
      if product&.client&.name.present? && product.groupwares.any?
        client_initials = product.client.name.split.map { |word| word[0] }.join.upcase
        groupware_initials = product.groupwares.map { |gw| gw.name.split.map { |w| w[0] }.join.upcase }.join
        "#{client_initials}#{groupware_initials}"
      else
        'DEFAULT'
      end

    # 👇 include soft-deleted defects
    last_task =
      Task.with_deleted
        .where(product_id: product_id)
        .where("unique_task_id ~ '^[^-]+-\\d+$'")
        .order(Arel.sql("CAST(SPLIT_PART(unique_task_id, '-', 2) AS INTEGER) DESC"))
        .first ||
      Task.with_deleted.where(product_id: product_id).order(:created_at).last

    next_number =
      if last_task&.unique_task_id.present?
        last_task.unique_task_id.split('-').last.to_i + 1
      else
        1
      end

    loop do
      self.unique_task_id = "#{initials}-#{next_number.to_s.rjust(4, '0')}"
      # 👇 check existence including soft-deleted
      break unless Task.with_deleted.exists?(unique_task_id: unique_task_id)

      next_number += 1
    end

    # Use update_column to avoid triggering callbacks again
    if persisted?
      update_column(:unique_task_id, unique_task_id)
    else
      save
    end
  end

  private

  def unique_task_id_missing?
    unique_task_id.blank?
  end

  def end_date_after_start_date
    return unless end_date.present? && start_date.present? && end_date < start_date

    errors.add(:end_date, 'End Date must be greater than Start Date')
  end

  # Ensure uploaded image is an actual image
  def image_must_be_an_image
    return unless image.attached?

    return if image.content_type.starts_with?('image/')

    errors.add(:image, 'must be an image file (jpeg, jpg, gif, or png).')
  end

  # Ensure uploaded file is a generic valid file
  def file_must_be_a_file
    return unless file.attached?

    return if file.content_type.start_with?('application/') || file.content_type.start_with?('text/')

    errors.add(:file, 'must be a valid file (pdf, doc, txt, etc.).')
  end
end
