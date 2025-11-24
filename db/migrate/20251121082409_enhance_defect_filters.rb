class EnhanceDefectFilters < ActiveRecord::Migration[7.2]
  def change
    # Add new columns (is_dashboard and chart_config already exist)
    add_column :defect_filters, :filter_rules, :jsonb, default: {} unless column_exists?(:defect_filters, :filter_rules)
    add_column :defect_filters, :display_order, :integer unless column_exists?(:defect_filters, :display_order)
    
    # GIN index for fast JSON queries on filter_rules
    add_index :defect_filters, :filter_rules, using: :gin unless index_exists?(:defect_filters, :filter_rules)
    add_index :defect_filters, [:user_id, :is_dashboard] unless index_exists?(:defect_filters, [:user_id, :is_dashboard])
  end
end
