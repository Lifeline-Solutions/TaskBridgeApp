class AddQaModuleReferencesToDefects < ActiveRecord::Migration[7.2]
  def change
    add_column :defects, :qa_module_id, :uuid
    add_column :defects, :submodule_id, :uuid
    
    add_index :defects, :qa_module_id
    add_index :defects, :submodule_id
    
    # Optional: Add foreign key constraints if desired
    add_foreign_key :defects, :qa_modules, column: :qa_module_id
    add_foreign_key :defects, :qa_modules, column: :submodule_id
  end
end
