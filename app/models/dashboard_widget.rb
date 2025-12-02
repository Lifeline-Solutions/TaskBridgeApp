# DashboardWidget - Represents a dashboard created from a saved filter
# Displays defects matching the filter criteria with a chosen visualization type
#
# Example:
#   dashboard = DashboardWidget.create!(
#     name: "High Priority Issues",
#     defect_filter_id: 99,
#     visualization_type: :table,
#     user: current_user
#   )
class DashboardWidget < ApplicationRecord
  include Auditable
  include SoftDeletable

  belongs_to :user
  belongs_to :defect_filter
  belongs_to :created_by, class_name: 'User', foreign_key: 'created_by', optional: true
  belongs_to :modified_by, class_name: 'User', foreign_key: 'modified_by', optional: true

  # JSON configuration for chart appearance
  # { colors: [...], title: "...", height: 400 }
  attribute :chart_config, :jsonb, default: -> { {} }

  # Refresh interval in seconds (optional)
  attribute :refresh_interval, :integer

  validates :name, presence: true, length: { maximum: 200 }
  validates :defect_filter_id, presence: true

  scope :active, -> { where(deleted_on: nil, archive_status: false) }
  scope :ordered, -> { order(created_at: :desc) }

  # Get the defects filtered by the saved filter
  def filtered_defects
    defect_filter.apply_to(Defect.published)
  end

  # Generate the dashboard data based on active filter parameters
  # Returns defects collection or aggregated data depending on visualization type
  def generate_data
    DashboardDataGenerator.new(self).generate
  end

  # Get active parameters from the filter for display
  def active_filter_parameters
    defect_filter.sanitized_filters.reject { |_k, v| v.blank? }
  end

  # Refresh the dashboard data
  def refresh!
    generate_data
  end
end
