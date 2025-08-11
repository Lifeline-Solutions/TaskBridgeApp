class Groupware < ApplicationRecord
  belongs_to :software
  has_many :scripts, dependent: :nullify
  belongs_to :user
  has_many :tickets, dependent: :nullify
  has_many :bugs, dependent: :nullify
  has_one_attached :image
  has_and_belongs_to_many :products
end
