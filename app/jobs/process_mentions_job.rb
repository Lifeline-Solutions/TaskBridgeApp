class ProcessMentionsJob < ApplicationJob
  queue_as :default

  def perform(content, defect_id, current_user_id, context_type = 'message')
    defect = Defect.find_by(id: defect_id)
    current_user = User.find_by(id: current_user_id)

    return unless defect && current_user

    begin
      mentioned_users = MentionNotificationService.process_mentions(
        content,
        defect,
        current_user,
        context_type
      )

      # Ensure mentioned_users is always an array-like object
      mentioned_users ||= []
      mention_count = mentioned_users.respond_to?(:count) ? mentioned_users.count : 0

      Rails.logger.info "Processed #{mention_count} mentions for defect #{defect.defect_unique}"

      # Log activity for successful processing
      Activities.activity
        .caused_by(current_user)
        .performed_on(defect)
        .event('mentions.processed')
        .with_properties(
          mentioned_user_count: mention_count,
          context_type: context_type
        )
        .log("Processed #{mention_count} mentions in #{context_type}")
    rescue StandardError => e
      Rails.logger.error "Failed to process mentions for defect #{defect_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Log error activity
      Activities.activity
        .caused_by(current_user)
        .performed_on(defect)
        .event('mentions.processing_failed')
        .with_properties(
          error_message: e.message,
          context_type: context_type
        )
        .log("Failed to process mentions in #{context_type}: #{e.message}")

      # Re-raise in development/test for debugging
      raise e if Rails.env.development? || Rails.env.test?
    end
  end
end
