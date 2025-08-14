class CreateBankingTypes < ActiveRecord::Migration[7.2]
  def change
    create_table :banking_types, id: :uuid do |t|
      t.string :name

      t.timestamps
    end
  end
end
