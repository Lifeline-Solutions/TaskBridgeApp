class DefectMessage < ApplicationRecord
  belongs_to :user
  belongs_to :defect
end
