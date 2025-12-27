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

ActiveRecord::Schema[7.2].define(version: 2025_12_16_011928) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "action_text_rich_texts", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "active_storage_attachments", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.string "name", null: false
    t.string "record_type", null: false
    t.uuid "record_id", null: false
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "active_storage_blobs", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "active_storage_variant_records", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "add_statuses", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "ticket_id", null: false
    t.uuid "status_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "add_tasks", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "task_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "addusers", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "product_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "assignees", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "project_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "banking_types", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by_id"
    t.uuid "modified_by_id"
    t.uuid "deleted_by_id"
    t.datetime "deleted_on"
    t.boolean "archive_status", default: false, null: false
    t.uuid "product_id"
  end

  create_table "banking_types_products", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "banking_type_id", null: false
    t.uuid "product_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "boards", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.string "status"
    t.uuid "product_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "clients", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "comments", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "commonly_selected_clients", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "user_id", null: false
    t.uuid "client_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "dashboard_shares", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "dashboard_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dashboard_widgets", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.string "name", limit: 200, null: false
    t.uuid "user_id", null: false
    t.uuid "defect_filter_id", null: false
    t.jsonb "chart_config", default: {}
    t.integer "refresh_interval"
    t.uuid "created_by"
    t.uuid "modified_by"
    t.uuid "deleted_by"
    t.boolean "archive_status", default: false
    t.datetime "deleted_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dashboards", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.string "name", limit: 200, null: false
    t.text "description"
    t.uuid "user_id", null: false
    t.uuid "defect_filter_id", null: false
    t.integer "auto_refresh_interval"
    t.jsonb "widgets", default: []
    t.uuid "created_by"
    t.uuid "modified_by"
    t.uuid "deleted_by"
    t.boolean "archive_status", default: false
    t.datetime "deleted_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "visibility", default: 0
    t.jsonb "custom_fields", default: [], comment: "Array of custom field names selected for distribution visualization (status, reporter, assignee, labels, modules, submodules, banking_types)"
    t.index ["custom_fields"], name: "index_dashboards_on_custom_fields", using: :gin
  end

  create_table "default_defect_assignees", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by_id"
    t.uuid "modified_by_id"
    t.uuid "deleted_by_id"
    t.datetime "deleted_on"
    t.boolean "archive_status", default: false, null: false
  end

  create_table "defect_failure_reports", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "defect_filters", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
    t.jsonb "filter_rules", default: {}
    t.integer "display_order"
  end

  create_table "defect_histories", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "defect_id", null: false
    t.uuid "user_id", null: false
    t.string "history_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "history"
  end

  create_table "defect_labels", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "defect_id", null: false
    t.uuid "label_id", null: false
    t.uuid "created_by"
    t.uuid "modified_by"
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "defect_links", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "source_defect_id", null: false
    t.uuid "target_defect_id", null: false
    t.string "link_type", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "defect_messages", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "user_id", null: false
    t.uuid "defect_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by_id"
    t.uuid "modified_by_id"
    t.uuid "deleted_by_id"
    t.datetime "deleted_on"
    t.boolean "archive_status", default: false, null: false
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
  end

  create_table "defects", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "defects_users", id: false, force: :cascade do |t|
    t.uuid "defect_id", null: false
    t.uuid "user_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
  end

  create_table "documents", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.string "name"
    t.uuid "product_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "draft_defect_messages", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "user_id", null: false
    t.uuid "defect_id", null: false
    t.text "content"
    t.jsonb "mentions_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by_id"
    t.uuid "modified_by_id"
    t.uuid "deleted_by_id"
    t.datetime "deleted_on"
    t.boolean "archive_status", default: false, null: false
  end

  create_table "emails", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "events", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "groupwares", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "groupwares_products", id: false, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.uuid "groupware_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "groupwares_projects", id: false, force: :cascade do |t|
    t.uuid "project_id", null: false
    t.uuid "groupware_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "issues", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "labels", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.string "name", null: false
    t.uuid "created_by"
    t.uuid "modified_by"
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "locations", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "messages", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "messages_users", id: false, force: :cascade do |t|
    t.uuid "message_id", null: false
    t.uuid "user_id", null: false
  end

  create_table "milestones", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "notifications", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "products", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
    t.string "proxy_name"
  end

  create_table "products_scripts", id: false, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.uuid "script_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "products_softwares", id: false, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.uuid "software_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "products_statuses", id: false, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.uuid "status_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "projects", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "projects_softwares", id: false, force: :cascade do |t|
    t.uuid "project_id", null: false
    t.uuid "software_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "qa_modules", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.string "name"
    t.uuid "parent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.uuid "product_id"
  end

  create_table "ratings", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "roles", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.string "name"
    t.string "resource_type"
    t.uuid "resource_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "scripts", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "sla_tickets", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "softwares", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.string "name"
    t.string "description"
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "states", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "user_id", null: false
    t.uuid "task_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "statuses", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "statuses_tasks", id: false, force: :cascade do |t|
    t.uuid "task_id", null: false
    t.uuid "status_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "system_activities", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "taggings", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "ticket_id", null: false
    t.uuid "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "tasks", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "teams", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.string "name"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
    t.string "team_role"
  end

  create_table "teams_users", id: false, force: :cascade do |t|
    t.uuid "team_id", null: false
    t.uuid "user_id", null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "ticket_feedbacks", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "tickets", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "update_histories", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
    t.uuid "ticket_id"
    t.uuid "user_id"
    t.json "change_details", default: {}, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "users", id: false, force: :cascade do |t|
    t.uuid "id", default: -> { "gen_random_uuid()" }, null: false
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
  end

  create_table "users_roles", id: false, force: :cascade do |t|
    t.uuid "user_id"
    t.uuid "role_id"
    t.uuid "created_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "modified_by", default: "c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da", null: false
    t.uuid "deleted_by"
    t.datetime "deleted_on"
  end

  create_table "versions", id: false, force: :cascade do |t|
    t.bigserial "id", null: false
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
  end
end
