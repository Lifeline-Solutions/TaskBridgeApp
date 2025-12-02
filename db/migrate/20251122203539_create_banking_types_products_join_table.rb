class CreateBankingTypesProductsJoinTable < ActiveRecord::Migration[7.2]
  def change
    # Create many-to-many join table
    create_table :banking_types_products, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :banking_type_id, null: false
      t.uuid :product_id, null: false
      
      t.timestamps
    end

    add_index :banking_types_products, :banking_type_id
    add_index :banking_types_products, :product_id
    add_index :banking_types_products, [:banking_type_id, :product_id], 
              unique: true, 
              name: 'index_banking_types_products_unique'
    
    add_foreign_key :banking_types_products, :banking_types
    add_foreign_key :banking_types_products, :products
    
    # Migrate existing data: Create join records for existing banking_type -> product relationships
    reversible do |dir|
      dir.up do
        # For each existing banking type with a product_id, create a join record
        execute <<-SQL
          INSERT INTO banking_types_products (id, banking_type_id, product_id, created_at, updated_at)
          SELECT gen_random_uuid(), id, product_id, created_at, updated_at
          FROM banking_types
          WHERE product_id IS NOT NULL
        SQL
      end
    end
    
    # Make product_id nullable for safety (keep column for now, can remove later)
    change_column_null :banking_types, :product_id, true
  end
end
