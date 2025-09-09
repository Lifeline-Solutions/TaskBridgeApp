class BankingType < ApplicationRecord
  has_many :defects, dependent: :nullify
end
