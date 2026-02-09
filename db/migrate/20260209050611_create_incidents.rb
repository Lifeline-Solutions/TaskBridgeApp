class CreateIncidents < ActiveRecord::Migration[7.2]
  def change
    create_table :incidents, id: :uuid do |t|
      t.references :task, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :event_type
      t.string :details
      t.references :assigned_user, foreign_key: { to_table: :users }, type: :uuid
      t.references :status, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
