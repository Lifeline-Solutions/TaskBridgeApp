class AddBankingTypeIdToDefects < ActiveRecord::Migration[7.2]
  def change
    add_column :defects, :banking_type_id, :uuid
    add_index :defects, :banking_type_id
    
    # Optional: Add foreign key constraint
    add_foreign_key :defects, :banking_types
  end
end
