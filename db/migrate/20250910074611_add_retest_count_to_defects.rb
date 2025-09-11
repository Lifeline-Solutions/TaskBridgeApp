class AddRetestCountToDefects < ActiveRecord::Migration[7.2]
  def change
    add_column :defects, :retest_count, :integer, default: 0, null: false
  end
end
