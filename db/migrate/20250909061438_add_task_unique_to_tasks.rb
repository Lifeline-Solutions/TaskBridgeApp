class AddTaskUniqueToTasks < ActiveRecord::Migration[7.2]
  def change
    add_column :tasks, :unique_task_id, :string, null: true
    add_index :tasks, :unique_task_id, unique: true, if_not_exists: true

  end
end
