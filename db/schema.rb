# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2025_08_26_130525) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "action_text_rich_texts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.uuid "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_action_text_rich_texts_on_deleted_on"
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.uuid "record_id", null: false
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["deleted_on"], name: "index_active_storage_attachments_on_deleted_on"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_active_storage_blobs_on_deleted_on"
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
    t.index ["deleted_on"], name: "index_active_storage_variant_records_on_deleted_on"
  end

  create_table "add_statuses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ticket_id", null: false
    t.uuid "status_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_add_statuses_on_deleted_on"
    t.index ["status_id"], name: "index_add_statuses_on_status_id"
    t.index ["ticket_id"], name: "index_add_statuses_on_ticket_id"
  end

  create_table "add_tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "task_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_add_tasks_on_deleted_on"
    t.index ["task_id"], name: "index_add_tasks_on_task_id"
    t.index ["user_id"], name: "index_add_tasks_on_user_id"
  end

  create_table "addusers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_addusers_on_deleted_on"
    t.index ["product_id"], name: "index_addusers_on_product_id"
    t.index ["user_id"], name: "index_addusers_on_user_id"
  end

  create_table "assignees", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "project_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_assignees_on_deleted_on"
    t.index ["project_id"], name: "index_assignees_on_project_id"
    t.index ["user_id"], name: "index_assignees_on_user_id"
  end

  create_table "banking_types", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_banking_types_on_name", unique: true
  end

  create_table "boards", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "status"
    t.uuid "product_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_boards_on_deleted_on"
    t.index ["product_id"], name: "index_boards_on_product_id"
    t.index ["user_id"], name: "index_boards_on_user_id"
  end

  create_table "clients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "phone"
    t.string "address"
    t.string "client_contact_person"
    t.string "client_contact_phone_number"
    t.string "client_contact_person_email"
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "country_code"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_clients_on_deleted_on"
    t.index ["name"], name: "index_clients_on_name", unique: true
    t.index ["user_id"], name: "index_clients_on_user_id"
  end

  create_table "comments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ticket_id", null: false
    t.string "what"
    t.string "why"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.uuid "project_id"
    t.string "status"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_comments_on_deleted_on"
    t.index ["project_id"], name: "index_comments_on_project_id"
    t.index ["ticket_id"], name: "index_comments_on_ticket_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "commonly_selected_clients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "client_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["client_id"], name: "index_commonly_selected_clients_on_client_id"
    t.index ["deleted_on"], name: "index_commonly_selected_clients_on_deleted_on"
    t.index ["user_id"], name: "index_commonly_selected_clients_on_user_id"
  end

  create_table "defect_histories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "defect_id", null: false
    t.uuid "user_id", null: false
    t.string "history_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "history"
    t.index ["defect_id"], name: "index_defect_histories_on_defect_id"
    t.index ["user_id"], name: "index_defect_histories_on_user_id"
  end

  create_table "defect_messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "defect_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by_id"
    t.uuid "modified_by_id"
    t.uuid "deleted_by_id"
    t.datetime "deleted_on"
    t.boolean "archive_status", default: false, null: false
    t.index ["archive_status"], name: "index_defect_messages_on_archive_status"
    t.index ["created_by_id"], name: "index_defect_messages_on_created_by_id"
    t.index ["defect_id"], name: "index_defect_messages_on_defect_id"
    t.index ["deleted_by_id"], name: "index_defect_messages_on_deleted_by_id"
    t.index ["deleted_on"], name: "index_defect_messages_on_deleted_on"
    t.index ["modified_by_id"], name: "index_defect_messages_on_modified_by_id"
    t.index ["user_id"], name: "index_defect_messages_on_user_id"
  end

  create_table "defect_statuses", id: false, force: :cascade do |t|
    t.uuid "defect_id", null: false
    t.uuid "status_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["defect_id", "status_id"], name: "index_defect_statuses_on_defect_id_and_status_id"
    t.index ["deleted_on"], name: "index_defect_statuses_on_deleted_on"
    t.index ["status_id", "defect_id"], name: "index_defect_statuses_on_status_id_and_defect_id"
  end

  create_table "defects", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "priority"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.uuid "qa_module_id"
    t.uuid "submodule_id"
    t.uuid "banking_type_id"
    t.uuid "creator_id"
    t.uuid "product_id"
    t.string "summary"
    t.string "defect_unique"
    t.string "issue_type", default: "Bug"
    t.index ["banking_type_id"], name: "index_defects_on_banking_type_id"
    t.index ["creator_id"], name: "index_defects_on_creator_id"
    t.index ["defect_unique"], name: "index_defects_on_defect_unique", unique: true
    t.index ["deleted_on"], name: "index_defects_on_deleted_on"
    t.index ["product_id"], name: "index_defects_on_product_id"
    t.index ["qa_module_id"], name: "index_defects_on_qa_module_id"
    t.index ["submodule_id"], name: "index_defects_on_submodule_id"
  end

  create_table "defects_users", id: false, force: :cascade do |t|
    t.uuid "defect_id", null: false
    t.uuid "user_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["defect_id", "user_id"], name: "index_defects_users_on_defect_id_and_user_id"
    t.index ["deleted_on"], name: "index_defects_users_on_deleted_on"
    t.index ["user_id", "defect_id"], name: "index_defects_users_on_user_id_and_defect_id"
  end

  create_table "documents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.uuid "product_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_documents_on_deleted_on"
    t.index ["product_id"], name: "index_documents_on_product_id"
  end

  create_table "emails", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "mail_id"
    t.string "message_id"
    t.string "email_type"
    t.string "status", default: "queued", null: false
    t.string "priority", default: "normal", null: false
    t.string "from_address"
    t.text "to_addresses"
    t.text "cc_addresses"
    t.text "bcc_addresses"
    t.string "subject"
    t.text "body_html"
    t.text "body_text"
    t.string "party_type"
    t.uuid "party_id"
    t.string "source_type"
    t.uuid "source_id"
    t.jsonb "extra", default: {}
    t.datetime "dated"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.datetime "created_on"
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.datetime "modified_on"
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.string "email_conversation_id"
    t.string "reference_id"
    t.uuid "read_by"
    t.datetime "read_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_emails_on_created_at"
    t.index ["mail_id"], name: "index_emails_on_mail_id", unique: true
    t.index ["message_id"], name: "index_emails_on_message_id"
    t.index ["party_type", "party_id"], name: "index_emails_on_party_type_and_party_id"
    t.index ["priority"], name: "index_emails_on_priority"
    t.index ["source_type", "source_id"], name: "index_emails_on_source_type_and_source_id"
    t.index ["status"], name: "index_emails_on_status"
  end

  create_table "events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ticket_id", null: false
    t.uuid "user_id", null: false
    t.string "event_type"
    t.text "details"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_events_on_deleted_on"
    t.index ["ticket_id"], name: "index_events_on_ticket_id"
    t.index ["user_id"], name: "index_events_on_user_id"
  end

  create_table "groupwares", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.uuid "software_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "description"
    t.uuid "user_id"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_groupwares_on_deleted_on"
    t.index ["software_id"], name: "index_groupwares_on_software_id"
    t.index ["user_id"], name: "index_groupwares_on_user_id"
  end

  create_table "groupwares_products", id: false, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.uuid "groupware_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_groupwares_products_on_deleted_on"
    t.index ["groupware_id", "product_id"], name: "index_groupwares_products_on_groupware_id_and_product_id"
    t.index ["product_id", "groupware_id"], name: "index_groupwares_products_on_product_id_and_groupware_id"
  end

  create_table "groupwares_projects", id: false, force: :cascade do |t|
    t.uuid "project_id", null: false
    t.uuid "groupware_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_groupwares_projects_on_deleted_on"
    t.index ["groupware_id", "project_id"], name: "index_groupwares_projects_on_groupware_id_and_project_id", unique: true
    t.index ["project_id", "groupware_id"], name: "index_groupwares_projects_on_project_id_and_groupware_id", unique: true
  end

  create_table "issues", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "subject"
    t.uuid "ticket_id", null: false
    t.uuid "project_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "message_type", default: "external"
    t.string "unique_id"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_issues_on_deleted_on"
    t.index ["project_id"], name: "index_issues_on_project_id"
    t.index ["ticket_id"], name: "index_issues_on_ticket_id"
    t.index ["unique_id"], name: "index_issues_on_unique_id", unique: true
    t.index ["user_id"], name: "index_issues_on_user_id"
  end

  create_table "locations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_locations_on_deleted_on"
  end

  create_table "messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "content"
    t.string "message_type", default: "external"
    t.uuid "user_id", null: false
    t.uuid "task_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_messages_on_deleted_on"
    t.index ["task_id"], name: "index_messages_on_task_id"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "messages_users", id: false, force: :cascade do |t|
    t.uuid "message_id", null: false
    t.uuid "user_id", null: false
    t.index ["message_id", "user_id"], name: "index_messages_users_on_message_id_and_user_id"
    t.index ["user_id", "message_id"], name: "index_messages_users_on_user_id_and_message_id"
  end

  create_table "milestones", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.uuid "status_id", null: false
    t.decimal "percentage", precision: 5, scale: 2
    t.integer "amount"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "paid", default: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_milestones_on_deleted_on"
    t.index ["product_id"], name: "index_milestones_on_product_id"
    t.index ["status_id"], name: "index_milestones_on_status_id"
  end

  create_table "notifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "ticket_id", null: false
    t.string "message"
    t.boolean "read"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_notifications_on_deleted_on"
    t.index ["ticket_id"], name: "index_notifications_on_ticket_id"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "products", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "start_date"
    t.date "end_date"
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "software_id"
    t.uuid "client_id"
    t.uuid "groupware_id"
    t.uuid "script_id"
    t.text "document_name"
    t.string "status", default: "draft"
    t.integer "budget"
    t.boolean "archive_status", default: false, null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["client_id"], name: "index_products_on_client_id"
    t.index ["deleted_on"], name: "index_products_on_deleted_on"
    t.index ["groupware_id"], name: "index_products_on_groupware_id"
    t.index ["script_id"], name: "index_products_on_script_id"
    t.index ["software_id"], name: "index_products_on_software_id"
    t.index ["user_id"], name: "index_products_on_user_id"
  end

  create_table "products_scripts", id: false, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.uuid "script_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_products_scripts_on_deleted_on"
    t.index ["product_id", "script_id"], name: "index_products_scripts_on_product_id_and_script_id"
    t.index ["script_id", "product_id"], name: "index_products_scripts_on_script_id_and_product_id"
  end

  create_table "products_softwares", id: false, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.uuid "software_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_products_softwares_on_deleted_on"
    t.index ["product_id", "software_id"], name: "index_products_softwares_on_product_id_and_software_id", unique: true
    t.index ["software_id", "product_id"], name: "index_products_softwares_on_software_id_and_product_id", unique: true
  end

  create_table "products_statuses", id: false, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.uuid "status_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_products_statuses_on_deleted_on"
    t.index ["product_id", "status_id"], name: "index_products_statuses_on_product_id_and_status_id"
    t.index ["status_id", "product_id"], name: "index_products_statuses_on_status_id_and_product_id"
  end

  create_table "projects", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "title"
    t.string "description"
    t.date "start_date"
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "client_id"
    t.uuid "software_id"
    t.uuid "groupware_id"
    t.boolean "special", default: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["client_id"], name: "index_projects_on_client_id"
    t.index ["deleted_on"], name: "index_projects_on_deleted_on"
    t.index ["groupware_id"], name: "index_projects_on_groupware_id"
    t.index ["software_id"], name: "index_projects_on_software_id"
    t.index ["title"], name: "index_projects_on_title", unique: true
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "projects_softwares", id: false, force: :cascade do |t|
    t.uuid "project_id", null: false
    t.uuid "software_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_projects_softwares_on_deleted_on"
    t.index ["project_id", "software_id"], name: "index_projects_softwares_on_project_id_and_software_id", unique: true
    t.index ["software_id", "project_id"], name: "index_projects_softwares_on_software_id_and_project_id", unique: true
  end

  create_table "qa_modules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.uuid "parent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_qa_modules_on_deleted_on"
    t.index ["parent_id"], name: "index_qa_modules_on_parent_id"
  end

  create_table "ratings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "value"
    t.uuid "ticket_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.string "comment"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_ratings_on_deleted_on"
    t.index ["ticket_id"], name: "index_ratings_on_ticket_id"
    t.index ["user_id"], name: "index_ratings_on_user_id"
  end

  create_table "roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.string "resource_type"
    t.uuid "resource_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_roles_on_deleted_on"
    t.index ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id"
    t.index ["resource_type", "resource_id"], name: "index_roles_on_resource"
  end

  create_table "scripts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "module"
    t.uuid "groupware_id", null: false
    t.uuid "software_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.text "description"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_scripts_on_deleted_on"
    t.index ["groupware_id"], name: "index_scripts_on_groupware_id"
    t.index ["software_id"], name: "index_scripts_on_software_id"
  end

  create_table "sla_tickets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ticket_id", null: false
    t.string "sla_status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "sla_target_response_deadline"
    t.string "sla_resolution_deadline"
    t.uuid "user_id"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_sla_tickets_on_deleted_on"
    t.index ["ticket_id"], name: "index_sla_tickets_on_ticket_id"
    t.index ["user_id"], name: "index_sla_tickets_on_user_id"
  end

  create_table "softwares", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_softwares_on_deleted_on"
    t.index ["name"], name: "index_softwares_on_name", unique: true
    t.index ["user_id"], name: "index_softwares_on_user_id"
  end

  create_table "states", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "task_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_states_on_deleted_on"
    t.index ["task_id"], name: "index_states_on_task_id"
    t.index ["user_id"], name: "index_states_on_user_id"
  end

  create_table "status_bugs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "bug_id", null: false
    t.uuid "status_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["bug_id"], name: "index_status_bugs_on_bug_id"
    t.index ["deleted_on"], name: "index_status_bugs_on_deleted_on"
    t.index ["status_id"], name: "index_status_bugs_on_status_id"
  end

  create_table "statuses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_statuses_on_deleted_on"
    t.index ["user_id"], name: "index_statuses_on_user_id"
  end

  create_table "statuses_tasks", id: false, force: :cascade do |t|
    t.uuid "task_id", null: false
    t.uuid "status_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_statuses_tasks_on_deleted_on"
    t.index ["status_id", "task_id"], name: "index_statuses_tasks_on_status_id_and_task_id"
    t.index ["task_id", "status_id"], name: "index_statuses_tasks_on_task_id_and_status_id"
  end

  create_table "system_activities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "log_name"
    t.text "description"
    t.string "subject_type"
    t.uuid "subject_id"
    t.string "causer_type"
    t.uuid "causer_id"
    t.jsonb "properties", default: {}
    t.string "event"
    t.uuid "batch_uuid"
    t.datetime "deleted_on"
    t.uuid "deleted_by"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["causer_type", "causer_id"], name: "index_system_activities_on_causer_type_and_causer_id"
    t.index ["created_at"], name: "index_system_activities_on_created_at"
    t.index ["event"], name: "index_system_activities_on_event"
    t.index ["subject_type", "subject_id"], name: "index_system_activities_on_subject_type_and_subject_id"
  end

  create_table "taggings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ticket_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_taggings_on_deleted_on"
    t.index ["ticket_id"], name: "index_taggings_on_ticket_id"
    t.index ["user_id"], name: "index_taggings_on_user_id"
  end

  create_table "tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.uuid "product_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "start_date"
    t.date "end_date"
    t.string "priority"
    t.uuid "tasks_id"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_tasks_on_deleted_on"
    t.index ["product_id"], name: "index_tasks_on_product_id"
    t.index ["tasks_id"], name: "index_tasks_on_tasks_id"
    t.index ["user_id"], name: "index_tasks_on_user_id"
  end

  create_table "teams", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_teams_on_deleted_on"
  end

  create_table "teams_users", id: false, force: :cascade do |t|
    t.uuid "team_id", null: false
    t.uuid "user_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_teams_users_on_deleted_on"
    t.index ["team_id", "user_id"], name: "index_teams_users_on_team_id_and_user_id"
    t.index ["user_id", "team_id"], name: "index_teams_users_on_user_id_and_team_id"
  end

  create_table "tickets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "issue"
    t.string "priority"
    t.uuid "project_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status"
    t.datetime "initial_response_deadline"
    t.datetime "target_repair_deadline"
    t.datetime "resolution_deadline"
    t.string "remarks"
    t.string "unique_id"
    t.uuid "software_id"
    t.uuid "groupware_id"
    t.string "subject"
    t.integer "update_count", default: -1, null: false
    t.datetime "last_updated_at", precision: nil
    t.date "due_date"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_tickets_on_deleted_on"
    t.index ["groupware_id"], name: "index_tickets_on_groupware_id"
    t.index ["project_id"], name: "index_tickets_on_project_id"
    t.index ["software_id"], name: "index_tickets_on_software_id"
    t.index ["unique_id"], name: "index_tickets_on_unique_id", unique: true
    t.index ["user_id"], name: "index_tickets_on_user_id"
  end

  create_table "update_histories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ticket_id"
    t.uuid "user_id"
    t.json "change_details", default: {}, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_update_histories_on_deleted_on"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "first_name"
    t.string "last_name"
    t.boolean "first_login", default: false
    t.string "invitation_token"
    t.datetime "invitation_created_at"
    t.datetime "invitation_sent_at"
    t.datetime "invitation_accepted_at"
    t.integer "invitation_limit"
    t.string "invited_by_type"
    t.bigint "invited_by_id"
    t.integer "invitations_count", default: 0
    t.uuid "client_id"
    t.boolean "active", default: true
    t.uuid "location_id"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["client_id"], name: "index_users_on_client_id"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["deleted_on"], name: "index_users_on_deleted_on"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["invitation_token"], name: "index_users_on_invitation_token", unique: true
    t.index ["invited_by_id"], name: "index_users_on_invited_by_id"
    t.index ["invited_by_type", "invited_by_id"], name: "index_users_on_invited_by"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "users_roles", id: false, force: :cascade do |t|
    t.uuid "user_id"
    t.uuid "role_id"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_users_roles_on_deleted_on"
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id"
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  create_table "versions", force: :cascade do |t|
    t.string "whodunnit"
    t.datetime "created_at"
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.string "event", null: false
    t.text "object"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_versions_on_deleted_on"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "add_statuses", "statuses"
  add_foreign_key "add_statuses", "tickets", on_delete: :cascade
  add_foreign_key "add_tasks", "tasks"
  add_foreign_key "add_tasks", "users"
  add_foreign_key "addusers", "products"
  add_foreign_key "addusers", "users"
  add_foreign_key "assignees", "projects"
  add_foreign_key "assignees", "users"
  add_foreign_key "boards", "products"
  add_foreign_key "boards", "users"
  add_foreign_key "clients", "users"
  add_foreign_key "comments", "projects"
  add_foreign_key "comments", "tickets", on_delete: :cascade
  add_foreign_key "comments", "users"
  add_foreign_key "commonly_selected_clients", "clients"
  add_foreign_key "commonly_selected_clients", "users"
  add_foreign_key "defect_histories", "defects"
  add_foreign_key "defect_histories", "users"
  add_foreign_key "defect_messages", "defects"
  add_foreign_key "defect_messages", "users"
  add_foreign_key "defect_messages", "users", column: "created_by_id"
  add_foreign_key "defect_messages", "users", column: "deleted_by_id"
  add_foreign_key "defect_messages", "users", column: "modified_by_id"
  add_foreign_key "defect_statuses", "defects"
  add_foreign_key "defect_statuses", "statuses"
  add_foreign_key "defects", "banking_types"
  add_foreign_key "defects", "products"
  add_foreign_key "defects", "qa_modules"
  add_foreign_key "defects", "qa_modules", column: "submodule_id"
  add_foreign_key "defects", "users", column: "creator_id"
  add_foreign_key "documents", "products"
  add_foreign_key "events", "tickets", on_delete: :cascade
  add_foreign_key "events", "users"
  add_foreign_key "groupwares", "softwares"
  add_foreign_key "groupwares", "users"
  add_foreign_key "issues", "projects"
  add_foreign_key "issues", "tickets", on_delete: :cascade
  add_foreign_key "issues", "users"
  add_foreign_key "messages", "tasks"
  add_foreign_key "messages", "users"
  add_foreign_key "milestones", "products"
  add_foreign_key "milestones", "statuses"
  add_foreign_key "notifications", "tickets", on_delete: :cascade
  add_foreign_key "notifications", "users"
  add_foreign_key "products", "clients"
  add_foreign_key "products", "groupwares"
  add_foreign_key "products", "scripts"
  add_foreign_key "products", "softwares"
  add_foreign_key "products", "users"
  add_foreign_key "projects", "clients"
  add_foreign_key "projects", "groupwares"
  add_foreign_key "projects", "softwares"
  add_foreign_key "projects", "users"
  add_foreign_key "ratings", "tickets", on_delete: :cascade
  add_foreign_key "ratings", "users"
  add_foreign_key "scripts", "groupwares"
  add_foreign_key "scripts", "softwares"
  add_foreign_key "sla_tickets", "tickets", on_delete: :cascade
  add_foreign_key "sla_tickets", "users"
  add_foreign_key "softwares", "users"
  add_foreign_key "states", "tasks"
  add_foreign_key "states", "users"
  add_foreign_key "status_bugs", "statuses"
  add_foreign_key "statuses", "users"
  add_foreign_key "taggings", "tickets", on_delete: :cascade
  add_foreign_key "taggings", "users"
  add_foreign_key "tasks", "products"
  add_foreign_key "tasks", "tasks", column: "tasks_id"
  add_foreign_key "tasks", "users"
  add_foreign_key "tickets", "groupwares"
  add_foreign_key "tickets", "projects"
  add_foreign_key "tickets", "softwares"
  add_foreign_key "tickets", "users"
  add_foreign_key "users", "clients"
end
