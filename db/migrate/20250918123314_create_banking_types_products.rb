class CreateBankingTypesProducts < ActiveRecord::Migration[7.2]
  def change
    create_table :banking_types_products, id: :uuid do |t|
      t.uuid :product_id, null: false
      t.uuid :banking_type_id, null: false

      t.timestamps
    end

    add_index :banking_types_products, [:product_id, :banking_type_id], unique: true, name: "index_banking_types_products_on_product_and_banking_type"
    add_foreign_key :banking_types_products, :products
    add_foreign_key :banking_types_products, :banking_types
  end
end
