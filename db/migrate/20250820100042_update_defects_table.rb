class UpdateDefectsTable < ActiveRecord::Migration[7.2]
  def change
    add_reference :defects, :product, type: :uuid, foreign_key: true, index: true
    add_column :defects, :summary, :string, null: false
    remove_column :defects, :status, :string
    add_reference :defects, :status, type: :uuid, foreign_key: true, index: true
  end
end
