class CreateEmails < ActiveRecord::Migration[7.2]
  SYSTEM_USER_ID = 'c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da'

  def change
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')

    create_table :emails, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :mail_id
      t.string  :message_id
      t.string  :email_type
      t.string  :status, null: false, default: 'queued'
      t.string  :priority, null: false, default: 'normal'

      t.string  :from_address
      t.text    :to_addresses
      t.text    :cc_addresses
      t.text    :bcc_addresses
      t.string  :subject
      t.text    :body_html
      t.text    :body_text

      t.string  :party_type
      t.uuid    :party_id
      t.string  :source_type
      t.uuid    :source_id

      t.jsonb   :extra, default: {}
      t.datetime :dated

      t.uuid     :created_by,  null: false, default: SYSTEM_USER_ID
      t.datetime :created_on
      t.uuid     :modified_by, null: false, default: SYSTEM_USER_ID
      t.datetime :modified_on
      t.uuid     :deleted_by
      t.datetime :deleted_on

      t.string  :email_conversation_id
      t.string  :reference_id

      t.uuid     :read_by
      t.datetime :read_on

      t.timestamps
    end

    add_index :emails, :status
    add_index :emails, :priority
    add_index :emails, :mail_id, unique: true
    add_index :emails, :message_id
    add_index :emails, %i[source_type source_id]
    add_index :emails, %i[party_type party_id]
    add_index :emails, :created_at
  end
end
