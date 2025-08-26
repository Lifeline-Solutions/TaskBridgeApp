class CreateDefectsStatusesJoinTable < ActiveRecord::Migration[7.2]
  def change
    # Remove the existing status_id foreign key from defects
    remove_foreign_key :defects, :statuses
    remove_column :defects, :status_id

    # Create the join table with audit fields
    create_table :defect_statuses, id: false, force: :cascade do |t|
      t.uuid "defect_id", null: false
      t.uuid "status_id", null: false
      t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
      t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
      t.uuid "deleted_by"
      t.datetime "deleted_on"
      
      # Add timestamps if you want them (they're in your defects_users example but not explicitly shown)
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false

      t.index ["defect_id", "status_id"], name: "index_defect_statuses_on_defect_id_and_status_id"
      t.index ["deleted_on"], name: "index_defect_statuses_on_deleted_on"
      t.index ["status_id", "defect_id"], name: "index_defect_statuses_on_status_id_and_defect_id"
    end

    # Add foreign key constraints
    add_foreign_key :defect_statuses, :defects
    add_foreign_key :defect_statuses, :statuses
  end
end
