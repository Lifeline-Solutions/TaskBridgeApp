class DropBugsTable < ActiveRecord::Migration[7.2]
  def change
    remove_foreign_key :status_bugs, :bugs rescue nil
    remove_foreign_key :add_bugs, :bugs rescue nil

    drop_table :bugs, if_exists: true
  end
end
