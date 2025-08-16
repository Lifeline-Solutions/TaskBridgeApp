class Email < ApplicationRecord
  has_many_attached :attachments

  enum :status, {
    queued: 'queued',
    sending: 'sending',
    sent: 'sent',
    failed: 'failed'
  }, prefix: :status

  enum :priority, {
    low: 'low',
    normal: 'normal',
    important: 'important'
  }, prefix: :priority

  validates :status, inclusion: { in: statuses.keys }
  validates :priority, inclusion: { in: priorities.keys }

  def to=(arr)
    self.to_addresses = normalize_addresses(arr)
  end

  def cc=(arr)
    self.cc_addresses = normalize_addresses(arr)
  end

  def bcc=(arr)
    self.bcc_addresses = normalize_addresses(arr)
  end

  def to_list
    split_addresses(to_addresses)
  end

  def cc_list
    split_addresses(cc_addresses)
  end

  def bcc_list
    split_addresses(bcc_addresses)
  end

  def mark_sending!
    update_columns(status: 'sending', modified_on: Time.current)
  end

  def mark_sent!(message_id:)
    update_columns(status: 'sent', message_id: message_id, dated: Time.current, modified_on: Time.current)
  end

  def mark_failed!(reason:)
    extras = (extra || {}).merge(failure_reason: reason.to_s, failed_at: Time.current)
    update_columns(status: 'failed', extra: extras, modified_on: Time.current)
  end

  private

  # Ensure we never persist a disallowed from address (like example.com)
  before_validation :normalize_from_address

  def normalize_from_address
    allowed = ENV.fetch('MAIL_FROM', 'cspm@craftsilicon.com')
    candidate = from_address.to_s.strip
    return unless candidate.blank? || candidate.casecmp('no-reply@example.com').zero? || candidate.downcase.end_with?('@example.com')

    self.from_address = allowed
  end

  def normalize_addresses(value)
    case value
    when Array
      value.flatten.compact.map(&:to_s).reject(&:blank?).join(',')
    when String
      value
    else
      ''
    end
  end

  def split_addresses(value)
    (value.presence || '').split(',').map(&:strip).reject(&:blank?)
  end
end
