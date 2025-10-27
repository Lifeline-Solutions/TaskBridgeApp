class AddQaModuleReferencesToDefects < ActiveRecord::Migration[7.2]
  def change
    # Safe column additions
    unless column_exists?(:defects, :qa_module_id)
      add_column :defects, :qa_module_id, :uuid
    end
    
    unless column_exists?(:defects, :submodule_id)
      add_column :defects, :submodule_id, :uuid
    end
    
    # Safe index additions
    unless index_exists?(:defects, :qa_module_id)
      add_index :defects, :qa_module_id
    end
    
    unless index_exists?(:defects, :submodule_id)
      add_index :defects, :submodule_id
    end
    
    # Safe foreign key additions (only if columns and tables exist)
    if column_exists?(:defects, :qa_module_id) && table_exists?(:qa_modules)
      begin
        add_foreign_key :defects, :qa_modules, column: :qa_module_id
      rescue ActiveRecord::StatementInvalid
        # Foreign key might already exist, continue
        puts "Foreign key for qa_module_id might already exist, skipping..."
      end
    end
    
    if column_exists?(:defects, :submodule_id) && table_exists?(:qa_modules)
      begin
        add_foreign_key :defects, :qa_modules, column: :submodule_id
      rescue ActiveRecord::StatementInvalid
        # Foreign key might already exist, continue
        puts "Foreign key for submodule_id might already exist, skipping..."
      end
    end
  end
end
