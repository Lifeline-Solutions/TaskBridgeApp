class AddDefectUniqueToDefect < ActiveRecord::Migration[7.2]
  def change
    add_column :defects, :defect_unique, :string
    add_index :defects, :defect_unique, unique: true

  end
end
