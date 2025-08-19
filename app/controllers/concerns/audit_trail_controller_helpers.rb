# Include in ApplicationController to auto-apply audit trail in create/update/destroy.
# It hooks into standard controller actions via around_action helpers you call manually.
# Example:
#   class ProjectsController < ApplicationController
#     include AuditTrailControllerHelpers
#     before_action -> { audit_on_create(resource) }, only: :create
#     before_action -> { audit_on_update(resource) }, only: :update
#   end
module AuditTrailControllerHelpers
  private

  # Call in create actions after initializing the record, before save
  def audit_on_create(record)
    AuditTrailService.apply_create(record, current_user)
  end

  # Call in update actions before save
  def audit_on_update(record)
    AuditTrailService.apply_update(record, current_user)
  end

  # Call in destroy actions to soft-delete instead of hard delete
  # Expects record to be the AR instance you intend to destroy
  # Return value: if soft-deleted, halts with head :no_content or render as you prefer
  def audit_soft_delete(record)
    return true if (record.respond_to?(:deleted_on) || record.respond_to?(:deleted_by)) && AuditTrailService.soft_delete(record, current_user)

    false
  end
end
