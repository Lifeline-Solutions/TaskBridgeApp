class Incident < ApplicationRecord
  belongs_to :task
  belongs_to :user
  belongs_to :assigned_user, class_name: 'User', optional: true
  belongs_to :status
end
