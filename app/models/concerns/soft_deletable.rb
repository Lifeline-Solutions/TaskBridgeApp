# frozen_string_literal: true

# Add this concern to models you want to soft delete and filter by default.
# It adds a default_scope to hide soft-deleted rows and helpers to query/delete.
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    # Hide records with deleted_on set
    default_scope { where(deleted_on: nil) if column_names.include?('deleted_on') }

    scope :with_deleted, -> { unscope(where: :deleted_on) if column_names.include?('deleted_on') }
    scope :only_deleted, -> { with_deleted.where.not(deleted_on: nil) if column_names.include?('deleted_on') }

    def soft_deleted?
      self[:deleted_on].present?
    end

    # Performs soft delete via service, ensuring audit columns are set
    def soft_delete!(user)
      AuditTrailService.soft_delete(self, user)
    end

    # Override destroy to soft delete when possible
    def destroy
      if has_attribute?(:deleted_on) || has_attribute?(:deleted_by)
        AuditTrailService.soft_delete(self, defined?(Current) ? Current.user : nil)
      else
        super
      end
    end

    # Forcibly delete the record from DB
    def really_destroy!
      self.class.unscoped { super }
    end

    # Restore a soft-deleted record
    def restore!
      changes = {}
      changes[:deleted_on] = nil if has_attribute?(:deleted_on)
      changes[:deleted_by] = nil if has_attribute?(:deleted_by)
      return true if changes.empty?

      assign_attributes(changes)
      save(validate: false)
    end
  end
end
