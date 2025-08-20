class CreateQaModules < ActiveRecord::Migration[7.2]
  def change
    create_table :qa_modules, id: :uuid, if_not_exists: true do |t|
      t.string :name
      t.uuid :parent_id

      t.timestamps
    end

    add_index :qa_modules, :parent_id, if_not_exists: true
  end
end
