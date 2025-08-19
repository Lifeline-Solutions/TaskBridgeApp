# Mix into models to automatically set audit fields on create and update.
# Works alongside controller service, useful when records are created outside controllers.
module Auditable
  extend ActiveSupport::Concern

  included do
    before_create :_audit_set_created_by
    before_save :_audit_set_modified_by
  end

  private

  def _audit_set_created_by
    return unless has_attribute?(:created_by)

    uid = _current_uid
    self[:created_by] ||= uid
    self[:modified_by] ||= uid if has_attribute?(:modified_by)
  end

  def _audit_set_modified_by
    return unless has_attribute?(:modified_by)

    self[:modified_by] = _current_uid
  end

  def _current_uid
    user = Current.user if defined?(Current)
    return user.id if user.respond_to?(:id)

    AuditTrailService::SYSTEM_USER_ID
  end
end
