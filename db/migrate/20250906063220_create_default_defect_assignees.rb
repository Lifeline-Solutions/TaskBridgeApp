class CreateDefaultDefectAssignees < ActiveRecord::Migration[7.2]
  def change
    create_table :default_defect_assignees, id: :uuid do |t|
      t.uuid :user_id, null: false
      t.timestamps
    end

    add_index :default_defect_assignees, :user_id, unique: true
    add_foreign_key :default_defect_assignees, :users, column: :user_id
  end
end
