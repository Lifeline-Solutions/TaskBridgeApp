module Admin
  class EmailReportsController < ApplicationController
    skip_before_action :authenticate_user!
    before_action :authenticate_user!
    before_action :ensure_admin

    def index
      @retried_at = params[:retried_at]
      @failed_at = params[:failed_at]
      @sent_at = params[:sent_at]
      @created_on = params[:created_on]

      scope = Email.all

      scope = scope.where(retried_at: Date.parse(@retried_at).all_day) if @retried_at.present?

      scope = scope.where(failed_at: Date.parse(@failed_at).all_day) if @failed_at.present?

      scope = scope.where(sent_at: Date.parse(@sent_at).all_day) if @sent_at.present?

      scope = scope.where(created_on: Date.parse(@created_on).all_day) if @created_on.present?

      # Totals for the header/summary
      @total_emails = scope.count

      # Data for the table: Group by email_type (which seems to be `email_type` column based on schema)
      # We need counts of failed, sent, and total for each type.

      # We can use aggregation.
      @report_data = scope.group(:email_type).select(
        'email_type',
        'COUNT(*) as total_count',
        "COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed_count",
        "COUNT(CASE WHEN status = 'sent' THEN 1 END) as sent_count"
      ).map do |record|
        {
          email_type: record.email_type,
          failed: record.failed_count,
          sent: record.sent_count,
          total: record.total_count
        }
      end.sort_by { |row| -row[:total] }
    end

    private

    def ensure_admin
      return if current_user&.has_role?(:admin)

      redirect_to root_path, alert: 'Access denied.'
    end
  end
end
