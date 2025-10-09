class CreateDraftDefectMessages < ActiveRecord::Migration[7.2]
  def change
    create_table :draft_defect_messages, id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
      t.uuid :user_id, null: false
      t.uuid :defect_id, null: false
      t.text :content
      t.jsonb :mentions_data
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.uuid :created_by_id
      t.uuid :modified_by_id
      t.uuid :deleted_by_id
      t.datetime :deleted_on
      t.boolean :archive_status, default: false, null: false
      
      t.index [:user_id, :defect_id], unique: true, name: 'index_draft_defect_messages_on_user_and_defect'
      t.index :defect_id, name: 'index_draft_defect_messages_on_defect_id'
      t.index :user_id, name: 'index_draft_defect_messages_on_user_id'
      t.index :created_by_id, name: 'index_draft_defect_messages_on_created_by_id'
      t.index :modified_by_id, name: 'index_draft_defect_messages_on_modified_by_id'
      t.index :deleted_by_id, name: 'index_draft_defect_messages_on_deleted_by_id'
      t.index :deleted_on, name: 'index_draft_defect_messages_on_deleted_on'
      t.index :archive_status, name: 'index_draft_defect_messages_on_archive_status'
      t.index :updated_at, name: 'index_draft_defect_messages_on_updated_at'
    end

    add_foreign_key :draft_defect_messages, :users, column: :user_id
    add_foreign_key :draft_defect_messages, :defects, column: :defect_id
    add_foreign_key :draft_defect_messages, :users, column: :created_by_id
    add_foreign_key :draft_defect_messages, :users, column: :modified_by_id
    add_foreign_key :draft_defect_messages, :users, column: :deleted_by_id
  end
end
