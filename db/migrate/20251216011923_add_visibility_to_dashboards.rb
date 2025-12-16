class AddVisibilityToDashboards < ActiveRecord::Migration[7.2]
  def change
    add_column :dashboards, :visibility, :integer, default: 0
  end
end
