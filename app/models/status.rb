class Status < ApplicationRecord
  has_many :add_statuses
  has_many :tickets, through: :add_statuses, dependent: :destroy
  has_many :status_bugs
  has_and_belongs_to_many :defects, join_table: :defect_statuses, dependent: :destroy
  has_many :bugs, through: :status_bugs, dependent: :destroy
  has_and_belongs_to_many :products, dependent: :destroy
  has_and_belongs_to_many :tasks, dependent: :destroy
end
