class AddBankingTypeIdToDefects < ActiveRecord::Migration[7.2]
  def change
    # Safe column addition
    unless column_exists?(:defects, :banking_type_id)
      add_column :defects, :banking_type_id, :uuid
    end
    
    # Safe index addition
    unless index_exists?(:defects, :banking_type_id)
      add_index :defects, :banking_type_id
    end
    
    # Safe foreign key addition
    if column_exists?(:defects, :banking_type_id) && table_exists?(:banking_types)
      begin
        add_foreign_key :defects, :banking_types
      rescue ActiveRecord::StatementInvalid
        # Foreign key might already exist, continue
        puts "Foreign key for banking_type_id might already exist, skipping..."
      end
    end
  end
end
