class CreateDefectMessages < ActiveRecord::Migration[7.2]
  def change
    create_table :defect_messages, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :defect, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
