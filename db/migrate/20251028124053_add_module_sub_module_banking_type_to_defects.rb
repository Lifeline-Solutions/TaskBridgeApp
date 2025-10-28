class AddModuleSubModuleBankingTypeToDefects < ActiveRecord::Migration[7.2]
  def change
    add_column :defects, :qa_module_id, :uuid,  if_not_exists: true
    add_column :defects, :submodule_id, :uuid,  if_not_exists: true
    add_column :defects, :banking_type_id, :uuid,  if_not_exists: true

    add_index :defects, :qa_module_id
    add_index :defects, :submodule_id
    add_index :defects, :banking_type_id
  end
end
