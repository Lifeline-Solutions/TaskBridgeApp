class CreateDashboardsAndWidgets < ActiveRecord::Migration[7.2]
  def change
    # Create dashboards table
    create_table :dashboards, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false, limit: 200
      t.text :description
      t.integer :columns, default: 3, null: false
      t.boolean :is_default, default: false, null: false
      
      # Audit fields
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users }
      t.references :modified_by, type: :uuid, foreign_key: { to_table: :users }
      t.references :deleted_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :deleted_on
      
      # Archive flag
      t.boolean :archive_status, default: false, null: false
      
      t.timestamps null: false
    end

    # Create widgets table
    create_table :widgets, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :dashboard, type: :uuid, null: false, foreign_key: true
      t.references :defect_filter, type: :uuid, foreign_key: true
      
      t.string :widget_type, null: false, limit: 50
      t.string :title, null: false, limit: 200
      t.integer :position, default: 0
      t.integer :width, default: 1  # Grid columns to span
      t.integer :height, default: 1 # Grid rows to span
      t.jsonb :config, default: {}
      
      t.timestamps null: false
    end

    # Indexes for dashboards
    add_index :dashboards, [:user_id, :is_default]
    add_index :dashboards, :archive_status
    add_index :dashboards, :deleted_on
    add_index :dashboards, :name

    # Indexes for widgets
    add_index :widgets, :dashboard_id
    add_index :widgets, [:dashboard_id, :position]
    add_index :widgets, :widget_type
    add_index :widgets, :config, using: :gin
  end
end
