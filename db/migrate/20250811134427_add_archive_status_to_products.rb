class AddArchiveStatusToProducts < ActiveRecord::Migration[7.2]
  def change
     add_column :products, :archive_status, :boolean, default: false, null: false
  end
end
