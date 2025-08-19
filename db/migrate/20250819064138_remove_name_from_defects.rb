class RemoveNameFromDefects < ActiveRecord::Migration[7.2]
  def change
    remove_column :defects, :name, :string
  end
end
