class CreateDefectHistories < ActiveRecord::Migration[7.2]
  def change
    create_table :defect_histories, id: :uuid,  if_not_exists: true do |t|
      t.references :defect, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :history_type
      t.timestamps
    end
  end
end
