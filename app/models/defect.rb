class Defect < ApplicationRecord
  has_rich_text :content
  has_many_attached :images
  has_many_attached :videos
  has_many_attached :attachments
  belongs_to :qa_module, class_name: 'QaModule'
  belongs_to :submodule, class_name: 'QaModule', optional: true
  belongs_to :banking_type
  belongs_to :product
  belongs_to :creator, class_name: 'User'

  resourcify
  has_many :users, through: :roles, class_name: 'User', source: :users
  has_many :creators, -> { where(roles: { name: :admin }) }, class_name: 'User', through: :roles, source: :users
  has_many :editors, lambda {
    where(roles: { name: ['admin', 'project manager'] })
  }, class_name: 'User', through: :roles, source: :users

  has_and_belongs_to_many :users
  has_and_belongs_to_many :statuses, join_table: :defect_statuses

  def assigned_to?(user)
    users.include?(user)
  end

  def craftsilicon_users
    User.where('email LIKE ANY (array[?, ?, ?]) AND active = ?', '%@craftsilicon.com', '%@craftsilicon.co.tz', '%@little.africa', true)
  end

  before_create :set_default_status
  after_create :defect_unique_id

  private

  def set_default_status
    default_status = Status.find_by(name: 'TO DO')
    self.statuses << default_status if default_status
  end

  def defect_unique_id
    initials =
      if product&.client&.name.present?
        product.client.name.split.map { |word| word[0] }.join.upcase
      else
        'DEFAULT'
      end

    last_defect =
      Defect.where(product_id: product_id)
        .where("defect_unique ~ '^[^-]+-\\d+$'")
        .order(Arel.sql("CAST(SPLIT_PART(defect_unique, '-', 2) AS INTEGER) DESC"))
        .first ||
      Defect.where(product_id: product_id).order(:created_at).last

    next_number =
      if last_defect&.defect_unique.present?
        last_defect.defect_unique.split('-').last.to_i + 1
      else
        1
      end

    loop do
      self.defect_unique = "#{initials}-#{next_number.to_s.rjust(4, '0')}"
      break unless Defect.exists?(defect_unique: defect_unique)

      next_number += 1
    end

    save
  end
end
