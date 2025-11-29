# Dashboard - Represents a dashboard with multiple widgets based on a saved filter
# Each dashboard contains widgets that visualize defect data in different ways
#
# Example:
#   dashboard = Dashboard.create!(
#     name: "QA Overview",
#     description: "Dashboard showing all QA metrics",
#     defect_filter_id: filter.id,
#     user: current_user,
#     widgets: [
#       { name: "By Priority", group_by_field: "priority", visualization_type: 0, position: 0 },
#       { name: "By Status", group_by_field: "status", visualization_type: 1, position: 1 }
#     ]
#   )
class Dashboard < ApplicationRecord
  include Auditable
  include SoftDeletable

  # Associations
  belongs_to :user
  belongs_to :defect_filter
  belongs_to :created_by, class_name: 'User', foreign_key: 'created_by', optional: true
  belongs_to :modified_by, class_name: 'User', foreign_key: 'modified_by', optional: true

  # Visualization types (same as old DashboardWidget)
  VISUALIZATION_TYPES = {
    pie_chart: 0,
    bar_chart: 1,
    line_chart: 2,
    count: 3,
    table: 4
  }.freeze

  # Group by fields (what dimension to visualize)
  GROUPABLE_FIELDS = %w[
    priority status assignee reporter
    qa_module submodule banking_type label ageing
  ].freeze

  # Validations
  validates :name, presence: true, length: { maximum: 200 }
  validates :user, presence: true
  validates :defect_filter, presence: true
  validate :validate_widgets_structure

  # Scopes
  scope :active, -> { where(deleted_on: nil, archive_status: false) }
  scope :for_user, ->(user) { where(user: user) }

  # Default values
  attribute :widgets, :jsonb, default: []
  attribute :archive_status, :boolean, default: false

  # Widget helper methods
  def add_widget(name:, group_by_field:, visualization_type:, position: nil)
    position ||= widgets.length
    self.widgets = widgets + [{
      name: name,
      group_by_field: group_by_field,
      visualization_type: visualization_type,
      position: position
    }]
  end

  def remove_widget(index)
    self.widgets = widgets.reject.with_index { |_, i| i == index }
    reorder_widgets!
  end

  def reorder_widgets!
    self.widgets = widgets.map.with_index { |w, i| w.merge(position: i) }
  end

  # Get filtered defects based on the saved filter
  def filtered_defects
    defect_filter.apply_to(Defect.published)
  end

  # Get active parameters from the filter for display
  def active_filter_parameters
    defect_filter.sanitized_filters.reject { |_k, v| v.blank? }
  end

  # Generate data for a specific widget
  def generate_widget_data(widget_index)
    widget = widgets[widget_index]
    return {} unless widget

    WidgetDataGenerator.new(
      defect_filter: defect_filter,
      group_by_field: widget['group_by_field'],
      visualization_type: widget['visualization_type']
    ).generate
  end

  private

  def validate_widgets_structure
    return if widgets.blank?

    widgets.each_with_index do |widget, index|
      unless widget.is_a?(Hash)
        errors.add(:widgets, "Widget #{index} must be a hash")
        next
      end

      errors.add(:widgets, "Widget #{index} must have a name") unless widget['name'].present?
      errors.add(:widgets, "Widget #{index} must have a group_by_field") unless widget['group_by_field'].present?
      errors.add(:widgets, "Widget #{index} must have a visualization_type") unless widget['visualization_type'].present?

      errors.add(:widgets, "Widget #{index} has invalid group_by_field: #{widget['group_by_field']}") unless GROUPABLE_FIELDS.include?(widget['group_by_field'])

      errors.add(:widgets, "Widget #{index} has invalid visualization_type: #{widget['visualization_type']}") unless VISUALIZATION_TYPES.values.include?(widget['visualization_type'])
    end
  end
end
