class RemoveVisualizationTypeFromDashboardWidgets < ActiveRecord::Migration[7.2]
  def change
    remove_column :dashboard_widgets, :visualization_type, :integer
  end
end
