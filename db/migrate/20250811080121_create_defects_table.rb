class CreateDefectsTable < ActiveRecord::Migration[7.2]
  def change
    create_table :defects, id: :uuid do |t|
      t.string :name
      t.string :description
      t.date :start_date
      t.date :end_date
      t.uuid :product_id
      t.uuid :user_id
      t.string :submodule
      t.string :issue
      t.string :priority
      t.string :summary
      t.uuid :software_id
      t.uuid :groupware_id
      t.uuid :script_id
      t.string :label

      t.timestamps
    end
    add_index :defects, :product_id
    add_index :defects, :user_id
    add_index :defects, :software_id
    add_index :defects, :groupware_id
    add_index :defects, :script_id
  end
end
