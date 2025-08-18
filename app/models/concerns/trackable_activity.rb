module TrackableActivity
  extend ActiveSupport::Concern

  included do
    after_commit :log_activity_create, on: :create, unless: -> { is_a?(SystemActivity) }
    after_commit :log_activity_update, on: :update, unless: -> { is_a?(SystemActivity) }
    # Rely on SoftDeletable concern to call deleted_on set; hook here too
    after_commit :log_activity_destroy, on: :destroy, unless: -> { is_a?(SystemActivity) }
  end

  private

  def log_activity_create
    return if is_a?(SystemActivity)

    Activities.activity
      .caused_by(Current.user)
      .performed_on(self)
      .event('create')
      .with_properties(changes: saved_changes)
      .log("Created #{self.class.name}##{id}")
  rescue StandardError => e
    Rails.logger.debug("TrackableActivity create log failed: #{e.message}")
  end

  def log_activity_update
    return if is_a?(SystemActivity)

    # Skip if only audit fields changed
    filtered = saved_changes.except('updated_at', 'modified_by', 'created_by')
    return if filtered.blank?

    Activities.activity
      .caused_by(Current.user)
      .performed_on(self)
      .event('update')
      .with_properties(changes: filtered)
      .log("Updated #{self.class.name}##{id}")
  rescue StandardError => e
    Rails.logger.debug("TrackableActivity update log failed: #{e.message}")
  end

  def log_activity_destroy
    return if is_a?(SystemActivity)

    Activities.activity
      .caused_by(Current.user)
      .performed_on(self)
      .event('destroy')
      .with_properties(deleted_on: (respond_to?(:deleted_on) ? deleted_on : nil))
      .log("Destroyed #{self.class.name}##{id}")
  rescue StandardError => e
    Rails.logger.debug("TrackableActivity destroy log failed: #{e.message}")
  end
end
