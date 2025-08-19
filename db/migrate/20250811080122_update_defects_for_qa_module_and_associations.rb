class UpdateDefectsForQaModuleAndAssociations < ActiveRecord::Migration[7.2]
  def change
    remove_column :defects, :description, :string
    remove_column :defects, :start_date, :date
    remove_column :defects, :end_date, :date
    remove_column :defects, :product_id, :uuid
    remove_column :defects, :submodule, :string
    remove_column :defects, :issue, :string
    remove_column :defects, :software_id, :uuid
    remove_column :defects, :script_id, :uuid
    remove_column :defects, :label, :string
    remove_column :defects, :user_id, :uuid
    remove_column :defects, :groupware_id, :uuid
    remove_column :defects, :summary, :string

    add_reference :defects, :qa_module, type: :uuid, foreign_key: { to_table: :qa_modules }
    add_reference :defects, :submodule, type: :uuid, foreign_key: { to_table: :qa_modules }
    add_reference :defects, :banking_type, type: :uuid, foreign_key: true
    add_reference :defects, :creator, type: :uuid, foreign_key: { to_table: :users }
    add_column :defects, :status, :string, default: 'Bug', null: false
  end
end
