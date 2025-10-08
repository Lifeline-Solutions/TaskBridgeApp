class RemoveTableStatusBugs < ActiveRecord::Migration[7.2]
  def change
    drop_table :status_bugs
  end
end
