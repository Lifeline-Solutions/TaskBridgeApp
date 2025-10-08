class AddFilterTypeToDefectFilters < ActiveRecord::Migration[7.2]
   def change
    add_column :defect_filters, :filter_type, :string, default: 'defect', null: false
    add_column :defect_filters, :chart_config, :jsonb, default: {}
    add_column :defect_filters, :is_dashboard, :boolean, default: false, null: false
    add_index :defect_filters, :filter_type
    add_index :defect_filters, [:user_id, :name, :filter_type], unique: true, name: 'index_user_name_filter_type_unique'
    add_index :defect_filters, :is_dashboard
  end
end
