class Label < ApplicationRecord
  include SoftDeletable

  has_many :defect_labels, dependent: :destroy
  has_many :defects, through: :defect_labels

  validates :name, presence: true, length: { maximum: 50 }
  validates :name, format: { with: /\A[a-zA-Z0-9_-]+\z/, message: 'only letters, numbers, underscores, and hyphens allowed' }
  validate :unique_name_case_insensitive

  before_validation :normalize_name

  private

  def normalize_name
    return if name.blank?

    self.name = name.strip.gsub(/\s+/, '-').gsub(/-+/, '-').downcase
  end

  def unique_name_case_insensitive
    return if name.blank?

    return unless self.class.with_deleted.where('LOWER(name) = ?', name.downcase).where.not(id: id).exists?

    errors.add(:name, 'has already been taken')
  end
end
