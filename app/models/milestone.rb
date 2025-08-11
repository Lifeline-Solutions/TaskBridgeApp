class Milestone < ApplicationRecord
  belongs_to :product
  belongs_to :status

  validates :percentage, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :status_id, presence: true

  before_save :calculate_amount

  private

  def calculate_amount
    return unless percentage.present? && product&.budget.present?

    self.amount = (product.budget * percentage / 100).round
  end
end
