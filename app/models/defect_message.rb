class DefectMessage < ApplicationRecord
  belongs_to :defect
  belongs_to :user
  belongs_to :modified_by, class_name: 'User', optional: true
  has_rich_text :content

  # Enable file attachments for comments (stores in active_storage_attachments)
  # This allows Jira comment attachments to be imported and displayed
  has_many_attached :attachments

  def record_type
    'message'
  end
end
