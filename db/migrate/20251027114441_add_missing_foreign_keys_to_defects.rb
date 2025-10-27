class AddMissingForeignKeysToDefects < ActiveRecord::Migration[7.2]
  def change
    # Add all missing foreign key columns
    add_column :defects, :creator_id, :uuid
    
    # Add indexes
    add_index :defects, :creator_id
    
    # Add foreign key constraints (optional but recommended)
    add_foreign_key :defects, :users, column: :creator_id
  end
end
