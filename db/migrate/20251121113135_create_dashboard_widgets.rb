class CreateDashboardWidgets < ActiveRecord::Migration[7.2]
  def change
    create_table :dashboards, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false, limit: 200
      t.text :description
      t.uuid :user_id, null: false
      t.uuid :defect_filter_id, null: false
      
      # Auto-refresh interval in seconds (null means no auto-refresh)
      t.integer :auto_refresh_interval
      
      # Widgets configuration stored as JSONB array
      # Each widget: { name: "...", group_by_field: "...", visualization_type: 0, position: 0 }
      t.jsonb :widgets, default: []
      
      # Audit fields
      t.uuid :created_by
      t.uuid :modified_by
      t.uuid :deleted_by
      
      # Soft delete
      t.boolean :archive_status, default: false
      t.datetime :deleted_on

      t.timestamps
    end
    
    # Add foreign keys manually for UUID columns
    add_foreign_key :dashboards, :users, column: :user_id
    add_foreign_key :dashboards, :defect_filters, column: :defect_filter_id
    add_foreign_key :dashboards, :users, column: :created_by
    add_foreign_key :dashboards, :users, column: :modified_by
    add_foreign_key :dashboards, :users, column: :deleted_by
    
    add_index :dashboards, :user_id
    add_index :dashboards, :defect_filter_id
    add_index :dashboards, [:user_id, :deleted_on]
    add_index :dashboards, :widgets, using: :gin
  end
end
