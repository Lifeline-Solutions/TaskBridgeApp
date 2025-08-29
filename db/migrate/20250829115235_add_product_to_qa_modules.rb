class AddProductToQaModules < ActiveRecord::Migration[7.2]
  def change
    add_reference :qa_modules, :product, null: true, foreign_key: true, type: :uuid

    # If you want to backfill with a default product, uncomment and adjust:
    # default_product_id = Product.first&.id
    # QaModule.update_all(product_id: default_product_id)

    # Then, set NOT NULL constraint
    # change_column_null :qa_modules, :product_id, false
  end
end
