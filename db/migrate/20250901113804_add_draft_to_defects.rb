class AddDraftToDefects < ActiveRecord::Migration[7.2]
  def change
    add_column :defects, :draft, :boolean, default: false, null: false
  end
end
