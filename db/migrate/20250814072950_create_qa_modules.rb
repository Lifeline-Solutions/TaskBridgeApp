class CreateQaModules < ActiveRecord::Migration[7.2]
  def change
    create_table :qa_modules, id: :uuid do |t|
      t.string :name
      t.uuid :parent_id

      t.timestamps
    end
    add_index :qa_modules, :parent_id
  end
end