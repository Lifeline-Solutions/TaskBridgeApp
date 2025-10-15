class DefectMessage < ApplicationRecord
  belongs_to :defect
  belongs_to :user
  belongs_to :modified_by, class_name: 'User', optional: true
  has_rich_text :content

  def record_type
    'message'
  end
end
