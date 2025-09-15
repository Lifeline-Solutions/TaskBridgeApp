class DefectMessage < ApplicationRecord
  belongs_to :defect
  belongs_to :user
  has_rich_text :content

  def record_type
    'message'
  end
end
