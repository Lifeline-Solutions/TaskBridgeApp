class Defect < ApplicationRecord
  include SoftDeletable

  has_rich_text :content
  has_many_attached :images
  has_many_attached :videos
  has_many_attached :attachments
  has_many :defect_messages, dependent: :destroy
  belongs_to :qa_module, class_name: 'QaModule'
  belongs_to :submodule, class_name: 'QaModule', optional: true
  belongs_to :banking_type
  belongs_to :product
  belongs_to :creator, class_name: 'User'

  has_many :defect_labels, dependent: :destroy
  has_many :labels, through: :defect_labels
  has_many :defect_failure_reports, dependent: :destroy

  resourcify
  has_many :users, through: :roles, class_name: 'User', source: :users
  has_many :creators, -> { where(roles: { name: :admin }) }, class_name: 'User', through: :roles, source: :users
  has_many :editors, lambda {
    where(roles: { name: ['admin', 'project manager'] })
  }, class_name: 'User', through: :roles, source: :users

  has_and_belongs_to_many :users
  has_and_belongs_to_many :statuses, join_table: :defect_statuses, dependent: :destroy
  has_many :defect_histories

  # Struct we use to normalize timeline entries
  TimelineItem = Struct.new(:type, :record, :timestamp)

  # Returns an array of TimelineItem ordered by timestamp (oldest first by default)
  # `order: :asc` or `order: :desc`
  def timeline_items(order: :asc)
    # load messages and failure reports (don't strip columns with select!)
    messages = defect_messages
      .includes(:user) # eager load the user for rendering
      .where(archive_status: false, deleted_on: nil)

    failure_reports = defect_failure_reports
      .where(archive_status: false, deleted_on: nil)

    items = messages.map do |m|
      TimelineItem.new('message', m, m.created_at)
    end

    failure_reports.each do |r|
      # prefer captured_at for the failure report timestamp; fallback to created_at if needed
      ts = r.captured_at || r.created_at
      items << TimelineItem.new('failure_report', r, ts)
    end

    items.sort_by!(&:timestamp)
    items.reverse! if order == :desc
    items
  end

  def all_attachments
    # Attachments directly uploaded to this defect
    defect_attachments = attachments.attachments

    # Attachments embedded in comments/messages for this defect
    comment_attachments = defect_messages.flat_map do |msg|
      msg.content&.body&.attachments || []
    end

    (defect_attachments + comment_attachments).uniq
  end

  def assigned_to?(user)
    users.include?(user)
  end

  def craftsilicon_users
    User.where('email LIKE ANY (array[?, ?, ?]) AND active = ?', '%@craftsilicon.com', '%@craftsilicon.co.tz', '%@little.africa', true)
  end

  scope :drafts, -> { where(draft: true) }
  scope :published, -> { where(draft: false) }

  before_create :set_default_status
  before_create :set_default_issue_type
  after_create :defect_unique_id

  # Validations
  validates :summary, presence: true
  validates :priority, presence: true
  validates :issue_type, presence: true
  validates :product_id, presence: true
  validates :creator_id, presence: true
  # Add validation to ensure module belongs to selected project
  validate :qa_module_belongs_to_product

  private

  def qa_module_belongs_to_product
    return if product_id.blank? || qa_module_id.blank?

    return if QaModule.where(id: qa_module_id, product_id: product_id).exists?

    errors.add(:qa_module_id, 'must belong to the selected project')
  end

  def set_default_status
    return unless statuses.empty?

    default_status = Status.find_by(name: 'To Do')
    statuses << default_status if default_status
  end

  def set_default_issue_type
    self.issue_type ||= 'Bug'
  end

  def defect_unique_id
    initials =
      if product&.client&.name.present?
        product.client.name.split.map { |word| word[0] }.join.upcase
      else
        'DEFAULT'
      end

    # 👇 include soft-deleted defects
    last_defect =
      Defect.with_deleted
        .where(product_id: product_id)
        .where("defect_unique ~ '^[^-]+-\\d+$'")
        .order(Arel.sql("CAST(SPLIT_PART(defect_unique, '-', 2) AS INTEGER) DESC"))
        .first ||
      Defect.with_deleted.where(product_id: product_id).order(:created_at).last

    next_number =
      if last_defect&.defect_unique.present?
        last_defect.defect_unique.split('-').last.to_i + 1
      else
        1
      end

    loop do
      self.defect_unique = "#{initials}-#{next_number.to_s.rjust(4, '0')}"
      # 👇 check existence including soft-deleted
      break unless Defect.with_deleted.exists?(defect_unique: defect_unique)

      next_number += 1
    end

    save
  end
end
