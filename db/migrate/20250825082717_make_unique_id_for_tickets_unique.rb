class MakeUniqueIdForTicketsUnique < ActiveRecord::Migration[7.2]
  def change
    add_index :tickets, :unique_id, unique: true,  if_not_exists: true
  end
end
