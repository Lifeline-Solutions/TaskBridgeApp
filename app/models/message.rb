# app/models/message.rb
class Message < ApplicationRecord
  belongs_to :task

  belongs_to :author, class_name: 'User', foreign_key: 'user_id', inverse_of: :authored_messages
  has_and_belongs_to_many :users

  has_rich_text :content # This stores the rich text in `action_text_rich_texts`.
  has_many_attached :attachments # Allows multiple file uploads.

  before_save :set_message_type

  private

  def set_message_type
    self.message_type = 'internal'
  end

  # validates :content, presence: true
  # validates :message_type, inclusion: { in: %w[internal external] }

  def visible_to?(user)
    return true if message_type == 'external'
    return false if message_type == 'internal' && user&.client?

    true
  end
end
