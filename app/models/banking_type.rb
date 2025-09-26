class BankingType < ApplicationRecord
  has_many :defects, dependent: :nullify
  belongs_to :product
end
