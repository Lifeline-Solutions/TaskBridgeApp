class AddLabelsToDefects < ActiveRecord::Migration[7.2]
  def change
    unless column_exists?(:defects, :label)
      add_column :defects, :label, :string
    end
  end
end