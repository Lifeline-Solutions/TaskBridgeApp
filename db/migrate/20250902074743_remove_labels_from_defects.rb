class RemoveLabelsFromDefects < ActiveRecord::Migration[7.2]
  def change
    remove_column :defects, :label, :string if column_exists?(:defects, :label)
  end
end
