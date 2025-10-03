class CreateDefectFilters < ActiveRecord::Migration[7.2]
  def change
    create_table :defect_filters, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :product, type: :uuid, foreign_key: true
      t.string :name, null: false
      t.jsonb :filters, null: false, default: {}

      # Audit fields
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users }
      t.references :modified_by, type: :uuid, foreign_key: { to_table: :users }
      t.references :deleted_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :deleted_on

      # Archive flag
      t.boolean :archive_status, default: false, null: false

      # Misc indexes (keep these)
      t.index :archive_status
      t.index :deleted_on

      t.timestamps null: false
    end

    # GIN index for JSONB
    add_index :defect_filters, :filters, using: :gin
  end
end
