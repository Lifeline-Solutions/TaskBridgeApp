class AddCustomFieldsToDashboards < ActiveRecord::Migration[7.2]
  def change
    add_column :dashboards, :custom_fields, :jsonb, default: [], comment: "Array of custom field names selected for distribution visualization (status, reporter, assignee, labels, modules, submodules, banking_types)"
    add_index :dashboards, :custom_fields, using: :gin
  end
end
