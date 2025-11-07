class RemoveUniqueIndexFromBankingTypesName < ActiveRecord::Migration[7.2]
  def change
    # Remove the existing unique index on name
    remove_index :banking_types, name: "index_banking_types_on_name"

    # Recreate a non-unique index
    add_index :banking_types, :name
  end
end
