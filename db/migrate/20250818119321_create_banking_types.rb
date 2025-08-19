class CreateBankingTypes < ActiveRecord::Migration[7.2]
  def change
    create_table :banking_types, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :banking_types, :name, unique: true
  end
end