class FixDashboardWidgetsTables < ActiveRecord::Migration[7.2]
  def up
    # Drop the incorrectly named table
    drop_table :dashboard_widgets_tables if table_exists?(:dashboard_widgets_tables)
    
    # Create the correct dashboard_widgets table only if it doesn't exist
    # (In production it may already exist from the previous migration)
    return if table_exists?(:dashboard_widgets)
    
    create_table :dashboard_widgets, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false, limit: 200
      t.uuid :user_id, null: false
      t.uuid :defect_filter_id, null: false
      
      # Visualization configuration
      t.integer :visualization_type, null: false, default: 0
      t.string :group_by_field, null: false
      
      # Chart configuration stored as JSONB
      # { colors: [...], title: "...", height: 400 }
      t.jsonb :chart_config, default: {}
      
      # Position/order on dashboard
      t.integer :position, default: 0
      
      # Auto-refresh interval in seconds (null means no auto-refresh)
      t.integer :refresh_interval
      
      # Audit fields
      t.uuid :created_by
      t.uuid :modified_by
      t.uuid :deleted_by
      
      # Soft delete
      t.boolean :archive_status, default: false
      t.datetime :deleted_on

      t.timestamps
    end
    
    # Add foreign keys for UUID columns
    add_foreign_key :dashboard_widgets, :users, column: :user_id
    add_foreign_key :dashboard_widgets, :defect_filters, column: :defect_filter_id
    add_foreign_key :dashboard_widgets, :users, column: :created_by
    add_foreign_key :dashboard_widgets, :users, column: :modified_by
    add_foreign_key :dashboard_widgets, :users, column: :deleted_by
    
    # Add indexes for performance
    add_index :dashboard_widgets, :user_id
    add_index :dashboard_widgets, :defect_filter_id
    add_index :dashboard_widgets, [:user_id, :archive_status, :deleted_on]
    add_index :dashboard_widgets, :position
    add_index :dashboard_widgets, :chart_config, using: :gin
  end
  
  def down
    drop_table :dashboard_widgets if table_exists?(:dashboard_widgets)
    
    # Recreate the old table if rolling back
    create_table :dashboard_widgets_tables, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.timestamps
    end
  end
end
