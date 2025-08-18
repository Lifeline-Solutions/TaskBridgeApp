class SetAuditDefaultsForAllTables < ActiveRecord::Migration[7.2]
  SYSTEM_USER_ID = 'c5d5cc2c-5ab2-4301-811a-5b6e8e4f61da'

  TABLES = %i[
    action_text_rich_texts
    active_storage_attachments
    active_storage_blobs
    active_storage_variant_records
    add_statuses
    add_tasks
    addusers
    assignees
    banking_types
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
    TABLES.each do |t|
      # Set DB-level defaults for created_by and modified_by to avoid NOT NULL violations
      set_default_if_column_exists(t, :created_by, SYSTEM_USER_ID)
      set_default_if_column_exists(t, :modified_by, SYSTEM_USER_ID)
    end
  end

  def down
    TABLES.each do |t|
      remove_default_if_column_exists(t, :created_by)
      remove_default_if_column_exists(t, :modified_by)
    end
  end

  private

  def set_default_if_column_exists(table, column, default)
    return unless column_exists?(table, column)
    change_column_default table, column, from: nil, to: default
  end

  def remove_default_if_column_exists(table, column)
    return unless column_exists?(table, column)
    change_column_default table, column, from: SYSTEM_USER_ID, to: nil
  end
end
