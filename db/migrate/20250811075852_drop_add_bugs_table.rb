class DropAddBugsTable < ActiveRecord::Migration[7.2]
  def change
    drop_table :add_bugs, if_exists: true
  end
end
