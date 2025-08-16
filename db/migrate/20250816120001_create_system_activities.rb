class CreateSystemActivities < ActiveRecord::Migration[7.2]
  def change
    create_table :system_activities, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :log_name
      t.text    :description
      t.string  :subject_type
      t.uuid    :subject_id
      t.string  :causer_type
      t.uuid    :causer_id
      t.jsonb   :properties, default: {}
      t.string  :event
      t.uuid    :batch_uuid
      t.datetime :deleted_on
      t.uuid     :deleted_by
      t.uuid     :created_by,  null: false
      t.uuid     :modified_by, null: false

      t.timestamps
    end

    add_index :system_activities, [:subject_type, :subject_id]
    add_index :system_activities, [:causer_type, :causer_id]
    add_index :system_activities, :event
    add_index :system_activities, :created_at
  end
end