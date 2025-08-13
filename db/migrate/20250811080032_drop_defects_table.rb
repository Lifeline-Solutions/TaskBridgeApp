class DropDefectsTable < ActiveRecord::Migration[7.2]
  def change
    drop_table :defects, if_exists: true
  end
end
