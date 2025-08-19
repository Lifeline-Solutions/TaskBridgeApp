# AuditTrailService centralizes setting audit attributes on records.
# Usage (in controllers):
#   AuditTrailService.apply_create(record, current_user)
#   AuditTrailService.apply_update(record, current_user)
#   AuditTrailService.soft_delete(record, current_user)
class AuditTrailService
  SYSTEM_USER_ID = 'c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da'.freeze

  class << self
    def apply_create(record, user)
      uid = user_id_or_system(user)
      set_attr_if_supported(record, :created_by, uid) if record.respond_to?(:created_by)
      set_attr_if_supported(record, :modified_by, uid) if record.respond_to?(:modified_by)
      record
    end

    def apply_update(record, user)
      uid = user_id_or_system(user)
      set_attr_if_supported(record, :modified_by, uid) if record.respond_to?(:modified_by)
      record
    end

    # Soft-delete a record by setting deleted_by and deleted_on.
    # Returns true/false like ActiveRecord#update
    def soft_delete(record, user)
      uid = user_id_or_system(user)
      changed = false

      if record.respond_to?(:deleted_by)
        record[:deleted_by] = uid
        changed = true
      end
      if record.respond_to?(:deleted_on)
        record[:deleted_on] = Time.current
        changed = true
      end

      return true unless changed # nothing to do

      save_without_validations(record)
    end

    private

    def user_id_or_system(user)
      return SYSTEM_USER_ID if user.nil?

      # Support UUID or integer primary keys
      if user.respond_to?(:id)
        user.id
      else
        begin
          user[:id]
        rescue StandardError
          SYSTEM_USER_ID
        end || SYSTEM_USER_ID
      end
    end

    def set_attr_if_supported(record, attr, value)
      record[attr] = value if record.has_attribute?(attr)
    end

    def save_without_validations(record)
      if record.respond_to?(:save)
        # Avoid validation failures when only audit fields change
        record.save(validate: false)
      else
        true
      end
    end
  end
end
