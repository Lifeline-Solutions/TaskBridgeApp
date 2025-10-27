class AddMissingForeignKeysToDefects < ActiveRecord::Migration[7.2]
  def change
    # Safe column addition
    unless column_exists?(:defects, :creator_id)
      add_column :defects, :creator_id, :uuid
    end
    
    # Safe index addition
    unless index_exists?(:defects, :creator_id)
      add_index :defects, :creator_id
    end
    
    # Safe foreign key addition
    if column_exists?(:defects, :creator_id) && table_exists?(:users)
      begin
        add_foreign_key :defects, :users, column: :creator_id
      rescue ActiveRecord::StatementInvalid
        # Foreign key might already exist, continue
        puts "Foreign key for creator_id might already exist, skipping..."
      end
    end
  end
end
