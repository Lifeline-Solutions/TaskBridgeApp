class AddProductIdToBankingTypes < ActiveRecord::Migration[7.2]
  def change
    add_reference :banking_types, :product, null: true, foreign_key: true, type: :uuid
  end
end
