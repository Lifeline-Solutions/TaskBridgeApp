class AddAuditableFieldsToBankingType < ActiveRecord::Migration[7.2]
  def change
    change_table :banking_types do |t|
      # Audit fields
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users }
      t.references :modified_by, type: :uuid, foreign_key: { to_table: :users }
      t.references :deleted_by, type: :uuid, foreign_key: { to_table: :users }
      t.datetime :deleted_on

      # Archive status
      t.boolean :archive_status, default: false, null: false

      # Indexes
      t.index :archive_status
      t.index :deleted_on
    end
  end
end
