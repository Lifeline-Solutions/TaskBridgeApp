class CreateDefectLinks < ActiveRecord::Migration[7.2]
  def change
    create_table :defect_links, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :source_defect, null: false, foreign_key: { to_table: :defects }, type: :uuid
      t.references :target_defect, null: false, foreign_key: { to_table: :defects }, type: :uuid
      t.string :link_type, null: false

      t.timestamps
      t.uuid :created_by, default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
      t.uuid :modified_by, default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
      t.uuid :deleted_by
      t.datetime :deleted_on
    end

    add_index :defect_links, [:source_defect_id, :target_defect_id], unique: true
    add_index :defect_links, :link_type
    add_index :defect_links, :deleted_on
  end
end
