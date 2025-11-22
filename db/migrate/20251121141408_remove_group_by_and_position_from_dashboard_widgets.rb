class RemoveGroupByAndPositionFromDashboardWidgets < ActiveRecord::Migration[7.2]
  def change
    remove_column :dashboard_widgets, :group_by_field, :string if column_exists?(:dashboard_widgets, :group_by_field)
    remove_column :dashboard_widgets, :position, :integer if column_exists?(:dashboard_widgets, :position)
  end
end
