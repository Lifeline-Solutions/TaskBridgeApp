class CreateQaModules < ActiveRecord::Migration[7.2]
  def change
    create_table :qa_modules, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :name
      t.uuid     :parent_id

      t.timestamps null: false

      t.uuid     :created_by,  null: false, default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da"
      t.uuid     :modified_by, null: false, default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da"
      t.uuid     :deleted_by
      t.datetime :deleted_on
    end

    add_index :qa_modules, :deleted_on, name: "index_qa_modules_on_deleted_on"
    add_index :qa_modules, :parent_id,  name: "index_qa_modules_on_parent_id"
  end
end
