class DraftDefectMessage < ApplicationRecord
  belongs_to :defect
  belongs_to :user
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :modified_by, class_name: 'User', optional: true
  belongs_to :deleted_by, class_name: 'User', optional: true, foreign_key: 'deleted_by_id'

  has_rich_text :content

  validates :user_id, uniqueness: { scope: :defect_id }

  before_create :set_created_by
  before_update :set_modified_by

  def self.find_for_user(defect, user)
    find_by(defect_id: defect.id, user_id: user.id)
  end

  def self.create_or_update_for_user(defect, user, attributes)
    draft = find_for_user(defect, user) || new(defect: defect, user: user)
    draft.update(attributes)
    draft
  end

  # Bypass audit system for draft cleanup
  def hard_delete
    self.class.delete(id)
  end

  def to_defect_message
    DefectMessage.new(
      defect: defect,
      user: user,
      content: content,
      created_by: user
    )
  end

  private

  def set_created_by
    self.created_by ||= user
  end

  def set_modified_by
    self.modified_by = user
  end
end
