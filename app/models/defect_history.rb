class DefectHistory < ApplicationRecord
  belongs_to :defect
  belongs_to :user
end
