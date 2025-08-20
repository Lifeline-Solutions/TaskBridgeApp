class DropBankingTypeTable < ActiveRecord::Migration[7.2]
  def change
    drop_table :banking_types
  end
end
