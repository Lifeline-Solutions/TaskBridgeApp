module ControllerActivity
  extend ActiveSupport::Concern

  included do
    after_action :log_controller_activity
  end

  private

  def log_controller_activity
    return unless defined?(Activities)
    return unless request
    # Only log write operations by default
    return unless %w[POST PUT PATCH DELETE].include?(request.request_method)

    begin
      return if is_a?(SystemActivitiesController)
    rescue StandardError
      false
    end

    # Build properties with minimal, safe context
    props = {
      controller: self.class.name,
      action: action_name,
      path: request.path,
      method: request.request_method,
      status: response&.status
    }

    # Light param snapshot (filter large/sensitive keys)
    if respond_to?(:params)
      filtered = begin
        params.to_unsafe_h
      rescue StandardError
        {}
      end
      filtered = filtered.dup
      %w[password password_confirmation token authenticity_token file attachment attachments content body].each { |k| filtered.delete(k) }
      props[:params] = filtered
    end

    Activities.activity
      .caused_by(defined?(Current) ? Current.user : nil)
      .event("#{controller_name}##{action_name}")
      .with_properties(props)
      .log("#{controller_name}##{action_name}")
  rescue StandardError => e
    Rails.logger.debug("ControllerActivity log failed: #{e.message}")
  end
end
