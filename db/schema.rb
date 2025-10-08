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

ActiveRecord::Schema[7.2].define(version: 2025_10_08_073744) do
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
    t.uuid "created_by_id"
    t.uuid "modified_by_id"
    t.uuid "deleted_by_id"
    t.datetime "deleted_on"
    t.boolean "archive_status", default: false, null: false
    t.uuid "product_id"
    t.index ["archive_status"], name: "index_banking_types_on_archive_status"
    t.index ["created_by_id"], name: "index_banking_types_on_created_by_id"
    t.index ["deleted_by_id"], name: "index_banking_types_on_deleted_by_id"
    t.index ["deleted_on"], name: "index_banking_types_on_deleted_on"
    t.index ["modified_by_id"], name: "index_banking_types_on_modified_by_id"
    t.index ["name"], name: "index_banking_types_on_name", unique: true
    t.index ["product_id"], name: "index_banking_types_on_product_id"
  end

  create_table "banking_types_products", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.uuid "banking_type_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "banking_type_id"], name: "index_banking_types_products_on_product_and_banking_type", unique: true
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

  create_table "default_defect_assignees", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by_id"
    t.uuid "modified_by_id"
    t.uuid "deleted_by_id"
    t.datetime "deleted_on"
    t.boolean "archive_status", default: false, null: false
    t.index ["archive_status"], name: "index_default_defect_assignees_on_archive_status"
    t.index ["created_by_id"], name: "index_default_defect_assignees_on_created_by_id"
    t.index ["deleted_by_id"], name: "index_default_defect_assignees_on_deleted_by_id"
    t.index ["deleted_on"], name: "index_default_defect_assignees_on_deleted_on"
    t.index ["modified_by_id"], name: "index_default_defect_assignees_on_modified_by_id"
    t.index ["user_id"], name: "index_default_defect_assignees_on_user_id", unique: true
  end

  create_table "defect_failure_reports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "defect_id", null: false
    t.integer "retest_number", null: false
    t.datetime "captured_at", null: false
    t.uuid "created_by_id"
    t.uuid "modified_by_id"
    t.uuid "deleted_by_id"
    t.datetime "deleted_on"
    t.boolean "archive_status", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["archive_status"], name: "index_defect_failure_reports_on_archive_status"
    t.index ["created_by_id"], name: "index_defect_failure_reports_on_created_by_id"
    t.index ["defect_id"], name: "index_defect_failure_reports_on_defect_id"
    t.index ["deleted_by_id"], name: "index_defect_failure_reports_on_deleted_by_id"
    t.index ["deleted_on"], name: "index_defect_failure_reports_on_deleted_on"
    t.index ["modified_by_id"], name: "index_defect_failure_reports_on_modified_by_id"
    t.index ["retest_number"], name: "index_defect_failure_reports_on_retest_number"
  end

  create_table "defect_filters", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "product_id"
    t.string "name", null: false
    t.jsonb "filters", default: {}, null: false
    t.uuid "created_by_id"
    t.uuid "modified_by_id"
    t.uuid "deleted_by_id"
    t.datetime "deleted_on"
    t.boolean "archive_status", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "filter_type", default: "defect", null: false
    t.jsonb "chart_config", default: {}
    t.boolean "is_dashboard", default: false, null: false
    t.index ["archive_status"], name: "index_defect_filters_on_archive_status"
    t.index ["created_by_id"], name: "index_defect_filters_on_created_by_id"
    t.index ["deleted_by_id"], name: "index_defect_filters_on_deleted_by_id"
    t.index ["deleted_on"], name: "index_defect_filters_on_deleted_on"
    t.index ["filter_type"], name: "index_defect_filters_on_filter_type"
    t.index ["filters"], name: "index_defect_filters_on_filters", using: :gin
    t.index ["is_dashboard"], name: "index_defect_filters_on_is_dashboard"
    t.index ["modified_by_id"], name: "index_defect_filters_on_modified_by_id"
    t.index ["product_id"], name: "index_defect_filters_on_product_id"
    t.index ["user_id", "name", "filter_type"], name: "index_user_name_filter_type_unique", unique: true
    t.index ["user_id"], name: "index_defect_filters_on_user_id"
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

  create_table "defect_labels", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "defect_id", null: false
    t.uuid "label_id", null: false
    t.uuid "created_by"
    t.uuid "modified_by"
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["defect_id", "label_id"], name: "index_defect_labels_on_defect_id_and_label_id", unique: true
    t.index ["defect_id"], name: "index_defect_labels_on_defect_id"
    t.index ["label_id"], name: "index_defect_labels_on_label_id"
  end

  create_table "defect_links", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "source_defect_id", null: false
    t.uuid "target_defect_id", null: false
    t.string "link_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.index ["deleted_on"], name: "index_defect_links_on_deleted_on"
    t.index ["link_type"], name: "index_defect_links_on_link_type"
    t.index ["source_defect_id", "target_defect_id"], name: "index_defect_links_on_source_defect_id_and_target_defect_id", unique: true
    t.index ["source_defect_id"], name: "index_defect_links_on_source_defect_id"
    t.index ["target_defect_id"], name: "index_defect_links_on_target_defect_id"
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
    t.boolean "draft", default: false, null: false
    t.integer "retest_count", default: 0, null: false
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
    t.uuid "assigned_user_id"
    t.index ["assigned_user_id"], name: "index_events_on_assigned_user_id"
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

  create_table "labels", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.uuid "created_by"
    t.uuid "modified_by"
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_labels_on_lower_name", unique: true
    t.index ["name"], name: "index_labels_on_name"
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

  create_table "motor_alert_locks", force: :cascade do |t|
    t.bigint "alert_id", null: false
    t.string "lock_timestamp", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["alert_id", "lock_timestamp"], name: "index_motor_alert_locks_on_alert_id_and_lock_timestamp", unique: true
    t.index ["alert_id"], name: "index_motor_alert_locks_on_alert_id"
  end

  create_table "motor_alerts", force: :cascade do |t|
    t.bigint "query_id", null: false
    t.string "name", null: false
    t.text "description"
    t.text "to_emails", null: false
    t.boolean "is_enabled", default: true, null: false
    t.text "preferences", null: false
    t.bigint "author_id"
    t.string "author_type"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "motor_alerts_name_unique_index", unique: true, where: "(deleted_at IS NULL)"
    t.index ["query_id"], name: "index_motor_alerts_on_query_id"
    t.index ["updated_at"], name: "index_motor_alerts_on_updated_at"
  end

  create_table "motor_api_configs", force: :cascade do |t|
    t.string "name", null: false
    t.string "url", null: false
    t.text "preferences", null: false
    t.text "credentials", null: false
    t.text "description"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "motor_api_configs_name_unique_index", unique: true, where: "(deleted_at IS NULL)"
  end

  create_table "motor_audits", force: :cascade do |t|
    t.string "auditable_id"
    t.string "auditable_type"
    t.string "associated_id"
    t.string "associated_type"
    t.bigint "user_id"
    t.string "user_type"
    t.string "username"
    t.string "action"
    t.text "audited_changes"
    t.bigint "version", default: 0
    t.text "comment"
    t.string "remote_address"
    t.string "request_uuid"
    t.datetime "created_at"
    t.index ["associated_type", "associated_id"], name: "motor_auditable_associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "motor_auditable_index"
    t.index ["created_at"], name: "index_motor_audits_on_created_at"
    t.index ["request_uuid"], name: "index_motor_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "motor_auditable_user_index"
  end

  create_table "motor_configs", force: :cascade do |t|
    t.string "key", null: false
    t.text "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_motor_configs_on_key", unique: true
    t.index ["updated_at"], name: "index_motor_configs_on_updated_at"
  end

  create_table "motor_dashboards", force: :cascade do |t|
    t.string "title", null: false
    t.text "description"
    t.text "preferences", null: false
    t.bigint "author_id"
    t.string "author_type"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["title"], name: "motor_dashboards_title_unique_index", unique: true, where: "(deleted_at IS NULL)"
    t.index ["updated_at"], name: "index_motor_dashboards_on_updated_at"
  end

  create_table "motor_forms", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.text "api_path", null: false
    t.string "http_method", null: false
    t.text "preferences", null: false
    t.bigint "author_id"
    t.string "author_type"
    t.datetime "deleted_at"
    t.string "api_config_name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "motor_forms_name_unique_index", unique: true, where: "(deleted_at IS NULL)"
    t.index ["updated_at"], name: "index_motor_forms_on_updated_at"
  end

  create_table "motor_note_tag_tags", force: :cascade do |t|
    t.bigint "tag_id", null: false
    t.bigint "note_id", null: false
    t.index ["note_id", "tag_id"], name: "motor_note_tags_note_id_tag_id_index", unique: true
    t.index ["tag_id"], name: "index_motor_note_tag_tags_on_tag_id"
  end

  create_table "motor_note_tags", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "motor_note_tags_name_unique_index", unique: true
  end

  create_table "motor_notes", force: :cascade do |t|
    t.text "body"
    t.bigint "author_id"
    t.string "author_type"
    t.string "record_id", null: false
    t.string "record_type", null: false
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id", "author_type"], name: "motor_notes_author_id_author_type_index"
    t.index ["record_id", "record_type"], name: "motor_notes_record_id_record_type_index"
  end

  create_table "motor_notifications", force: :cascade do |t|
    t.string "title", null: false
    t.text "description"
    t.bigint "recipient_id", null: false
    t.string "recipient_type", null: false
    t.string "record_id"
    t.string "record_type"
    t.string "status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recipient_id", "recipient_type"], name: "motor_notifications_recipient_id_recipient_type_index"
    t.index ["record_id", "record_type"], name: "motor_notifications_record_id_record_type_index"
  end

  create_table "motor_queries", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.text "sql_body", null: false
    t.text "preferences", null: false
    t.bigint "author_id"
    t.string "author_type"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "motor_queries_name_unique_index", unique: true, where: "(deleted_at IS NULL)"
    t.index ["updated_at"], name: "index_motor_queries_on_updated_at"
  end

  create_table "motor_reminders", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.string "author_type", null: false
    t.bigint "recipient_id", null: false
    t.string "recipient_type", null: false
    t.string "record_id"
    t.string "record_type"
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id", "author_type"], name: "motor_reminders_author_id_author_type_index"
    t.index ["recipient_id", "recipient_type"], name: "motor_reminders_recipient_id_recipient_type_index"
    t.index ["record_id", "record_type"], name: "motor_reminders_record_id_record_type_index"
    t.index ["scheduled_at"], name: "index_motor_reminders_on_scheduled_at"
  end

  create_table "motor_resources", force: :cascade do |t|
    t.string "name", null: false
    t.text "preferences", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_motor_resources_on_name", unique: true
    t.index ["updated_at"], name: "index_motor_resources_on_updated_at"
  end

  create_table "motor_taggable_tags", force: :cascade do |t|
    t.bigint "tag_id", null: false
    t.bigint "taggable_id", null: false
    t.string "taggable_type", null: false
    t.index ["tag_id"], name: "index_motor_taggable_tags_on_tag_id"
    t.index ["taggable_id", "taggable_type", "tag_id"], name: "motor_polymorphic_association_tag_index", unique: true
  end

  create_table "motor_tags", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "motor_tags_name_unique_index", unique: true
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
    t.uuid "product_id"
    t.index ["parent_id"], name: "index_qa_modules_on_parent_id"
    t.index ["product_id"], name: "index_qa_modules_on_product_id"
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
    t.string "unique_task_id"
    t.index ["deleted_on"], name: "index_tasks_on_deleted_on"
    t.index ["product_id"], name: "index_tasks_on_product_id"
    t.index ["tasks_id"], name: "index_tasks_on_tasks_id"
    t.index ["unique_task_id"], name: "index_tasks_on_unique_task_id", unique: true
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

  create_table "ticket_feedbacks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ticket_id", null: false
    t.integer "rating", null: false
    t.uuid "creator_id", null: false
    t.datetime "captured_at", null: false
    t.uuid "modified_by_id"
    t.uuid "deleted_by_id"
    t.datetime "deleted_on"
    t.boolean "archive_status", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_ticket_feedbacks_on_creator_id"
    t.index ["ticket_id"], name: "index_ticket_feedbacks_on_ticket_id"
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
    t.integer "feedback_count", default: 0, null: false
    t.index ["deleted_on"], name: "index_tickets_on_deleted_on"
    t.index ["feedback_count"], name: "index_tickets_on_feedback_count"
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
  add_foreign_key "add_statuses", "tickets"
  add_foreign_key "add_tasks", "tasks"
  add_foreign_key "add_tasks", "users"
  add_foreign_key "addusers", "products"
  add_foreign_key "addusers", "users"
  add_foreign_key "assignees", "projects"
  add_foreign_key "assignees", "users"
  add_foreign_key "banking_types", "products"
  add_foreign_key "banking_types", "users", column: "created_by_id"
  add_foreign_key "banking_types", "users", column: "deleted_by_id"
  add_foreign_key "banking_types", "users", column: "modified_by_id"
  add_foreign_key "banking_types_products", "banking_types"
  add_foreign_key "banking_types_products", "products"
  add_foreign_key "boards", "products"
  add_foreign_key "boards", "users"
  add_foreign_key "clients", "users"
  add_foreign_key "comments", "projects"
  add_foreign_key "comments", "tickets"
  add_foreign_key "comments", "users"
  add_foreign_key "commonly_selected_clients", "clients"
  add_foreign_key "commonly_selected_clients", "users"
  add_foreign_key "default_defect_assignees", "users"
  add_foreign_key "default_defect_assignees", "users", column: "created_by_id"
  add_foreign_key "default_defect_assignees", "users", column: "deleted_by_id"
  add_foreign_key "default_defect_assignees", "users", column: "modified_by_id"
  add_foreign_key "defect_failure_reports", "defects"
  add_foreign_key "defect_failure_reports", "users", column: "created_by_id"
  add_foreign_key "defect_failure_reports", "users", column: "deleted_by_id"
  add_foreign_key "defect_failure_reports", "users", column: "modified_by_id"
  add_foreign_key "defect_filters", "products"
  add_foreign_key "defect_filters", "users"
  add_foreign_key "defect_filters", "users", column: "created_by_id"
  add_foreign_key "defect_filters", "users", column: "deleted_by_id"
  add_foreign_key "defect_filters", "users", column: "modified_by_id"
  add_foreign_key "defect_histories", "defects"
  add_foreign_key "defect_histories", "users"
  add_foreign_key "defect_links", "defects", column: "source_defect_id"
  add_foreign_key "defect_links", "defects", column: "target_defect_id"
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
  add_foreign_key "events", "tickets"
  add_foreign_key "events", "users"
  add_foreign_key "events", "users", column: "assigned_user_id"
  add_foreign_key "groupwares", "softwares"
  add_foreign_key "groupwares", "users"
  add_foreign_key "issues", "projects"
  add_foreign_key "issues", "tickets"
  add_foreign_key "issues", "users"
  add_foreign_key "messages", "tasks"
  add_foreign_key "messages", "users"
  add_foreign_key "milestones", "products"
  add_foreign_key "milestones", "statuses"
  add_foreign_key "motor_alert_locks", "motor_alerts", column: "alert_id"
  add_foreign_key "motor_alerts", "motor_queries", column: "query_id"
  add_foreign_key "motor_note_tag_tags", "motor_note_tags", column: "tag_id"
  add_foreign_key "motor_note_tag_tags", "motor_notes", column: "note_id"
  add_foreign_key "motor_taggable_tags", "motor_tags", column: "tag_id"
  add_foreign_key "notifications", "tickets"
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
  add_foreign_key "qa_modules", "products"
  add_foreign_key "ratings", "tickets"
  add_foreign_key "ratings", "users"
  add_foreign_key "scripts", "groupwares"
  add_foreign_key "scripts", "softwares"
  add_foreign_key "sla_tickets", "tickets"
  add_foreign_key "sla_tickets", "users"
  add_foreign_key "softwares", "users"
  add_foreign_key "states", "tasks"
  add_foreign_key "states", "users"
  add_foreign_key "statuses", "users"
  add_foreign_key "taggings", "tickets"
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
