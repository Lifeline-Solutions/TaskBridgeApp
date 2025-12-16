class DashboardShare < ApplicationRecord
  belongs_to :dashboard
  belongs_to :user
end
