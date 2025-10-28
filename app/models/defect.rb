class Defect < ApplicationRecord
  include Auditable
  include TrackableActivity
  include SoftDeletable

  belongs_to :creator, class_name: 'User', foreign_key: 'created_by', optional: true
  belongs_to :modifier, class_name: 'User', foreign_key: 'modified_by', optional: true

  has_rich_text :content
  has_many_attached :images
  has_many_attached :videos
  has_many_attached :attachments
  has_many :defect_messages, dependent: :destroy
  belongs_to :qa_module, class_name: 'QaModule', optional: true
  belongs_to :submodule, class_name: 'QaModule', optional: true
  belongs_to :banking_type, optional: true
  belongs_to :product, optional: true
  # belongs_to :creator, class_name: 'User'

  has_many :defect_labels, dependent: :destroy
  has_many :labels, through: :defect_labels
  has_many :defect_failure_reports, dependent: :destroy

  # Defect linking associations
  has_many :source_links, class_name: 'DefectLink', foreign_key: 'source_defect_id', dependent: :destroy
  has_many :target_links, class_name: 'DefectLink', foreign_key: 'target_defect_id', dependent: :destroy

  # Get defects that this defect is blocked by (this defect is source, blocked_by type)
  def blocking_defects
    Defect.joins('INNER JOIN defect_links ON defects.id = defect_links.target_defect_id')
      .where('defect_links.source_defect_id = ? AND defect_links.link_type = ? AND defect_links.deleted_on IS NULL', id, DefectLink::BLOCKED_BY)
  end

  # Get defects that this defect blocks (this defect is source, blocks type)
  def blocked_defects
    Defect.joins('INNER JOIN defect_links ON defects.id = defect_links.target_defect_id')
      .where('defect_links.source_defect_id = ? AND defect_links.link_type = ? AND defect_links.deleted_on IS NULL', id, DefectLink::BLOCKS)
  end

  # Check if this defect is blocked by another defect
  def blocked?
    blocking_defects.exists?
  end

  # Get the defects that are blocking this defect (for display purposes)
  def blocking_defect_names
    blocking_defects.pluck(:defect_unique).join(', ')
  end

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
  # validates :creator_id, presence: true
  # Add validation to ensure module belongs to selected project
  validate :qa_module_belongs_to_product

  # Methods for linking defects
  def link_as_blocked_by(blocking_defect)
    return false if id == blocking_defect.id

    ActiveRecord::Base.transaction do
      # When defect A is blocked by defect B, create both relationships (like JIRA):
      # 1. Create a "blocked_by" link from A to B (A is blocked by B)
      DefectLink.find_or_create_by!(
        source_defect: self,
        target_defect: blocking_defect,
        link_type: DefectLink::BLOCKED_BY
      )

      # 2. Create a "blocks" link from B to A (B blocks A)
      DefectLink.find_or_create_by!(
        source_defect: blocking_defect,
        target_defect: self,
        link_type: DefectLink::BLOCKS
      )
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def unlink_from(other_defect)
    return false if id == other_defect.id

    ActiveRecord::Base.transaction do
      # Remove all links between these two defects (use delete_all for permanent removal)
      DefectLink.where(
        '(source_defect_id = ? AND target_defect_id = ?) OR (source_defect_id = ? AND target_defect_id = ?)',
        id, other_defect.id, other_defect.id, id
      ).delete_all
    end
    true
  end

  def linked_defects
    # Get all defects that are linked to this one (both blocking and blocked by)
    blocked_ids = blocked_defects.pluck(:id)
    blocking_ids = blocking_defects.pluck(:id)
    all_linked_ids = (blocked_ids + blocking_ids).uniq

    return Defect.none if all_linked_ids.empty?

    Defect.where(id: all_linked_ids).includes(:product)
  end

  def blocks?(other_defect)
    blocked_defects.exists?(id: other_defect.id)
  end

  def blocked_by?(other_defect)
    blocking_defects.exists?(id: other_defect.id)
  end

  private

  def qa_module_belongs_to_product
    # Skip validation if columns don't exist in DB
    return unless Defect.column_names.include?('qa_module_id') && Defect.column_names.include?('product_id')

    qa_module_id_val = self[:qa_module_id] if has_attribute?(:qa_module_id)
    product_id_val = self[:product_id] if has_attribute?(:product_id)

    return if qa_module_id_val.blank? || product_id_val.blank?

    return if QaModule.where(id: qa_module_id_val, product_id: product_id_val).exists?

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
