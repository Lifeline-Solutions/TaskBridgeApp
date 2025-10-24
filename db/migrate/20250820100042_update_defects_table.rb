class UpdateDefectsTable < ActiveRecord::Migration[7.2]
  def change
    add_reference :defects, :product, type: :uuid, foreign_key: true, index: true, if_not_exists: true
    add_column :defects, :summary, :string, null: true, if_not_exists: true
    
    # Remove the column only if it exists
    remove_column :defects, :status if column_exists?(:defects, :status)
    
    add_reference :defects, :status, type: :uuid, foreign_key: true, index: true
  end
end