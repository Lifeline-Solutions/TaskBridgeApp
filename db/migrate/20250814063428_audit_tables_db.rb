class AuditTablesDb < ActiveRecord::Migration[7.2]
  SYSTEM_USER_ID = 'c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da'
  AUDIT_COLUMNS = {
    created_by: :uuid,
    modified_by: :uuid,
    deleted_by: :uuid,
    deleted_on: :datetime
  }.freeze

  # Put only your application tables here. Avoid Rails/system tables.
  TARGET_TABLES = %i[
  action_text_rich_texts
  active_storage_attachments
  active_storage_blobs
  active_storage_variant_records
  add_statuses
  add_tasks
  addusers
  assignees
  boards
  clients
  comments
  commonly_selected_clients
  defects
  defects_users
  documents
  events
  groupwares
  groupwares_products
  groupwares_projects
  issues
  locations
  messages
  milestones
  notifications
  products
  products_scripts
  products_softwares
  products_statuses
  projects
  projects_softwares
  qa_modules
  ratings
  roles
  scripts
  sla_tickets
  softwares
  states
  status_bugs
  statuses
  statuses_tasks
  taggings
  tasks
  teams
  teams_users
  tickets
  update_histories
  users
  users_roles
  versions
  ].freeze

  def up
    TARGET_TABLES.each do |t|
      AUDIT_COLUMNS.each do |col, type|
        add_column t, col, type unless column_exists?(t, col)
      end
      add_index t, :deleted_on unless index_exists?(t, :deleted_on)

      execute <<~SQL.squish
        UPDATE #{quote_table_name(t)}
        SET created_by = COALESCE(created_by, '#{SYSTEM_USER_ID}'),
            modified_by = COALESCE(modified_by, '#{SYSTEM_USER_ID}')
      SQL

      change_column_null t, :created_by, false
      change_column_null t, :modified_by, false
    end
  end

  def down
    TARGET_TABLES.each do |t|
      remove_index  t, :deleted_on if index_exists?(t, :deleted_on)
      %i[deleted_on deleted_by modified_by created_by].each do |col|
        remove_column t, col if column_exists?(t, col)
      end
    end
  end
end
