class SystemActivitiesDefaults < ActiveRecord::Migration[7.2]
  def up
    # Ensure defaults for created_by/modified_by to SYSTEM_USER_ID
    execute <<~SQL
      ALTER TABLE system_activities
      ALTER COLUMN created_by SET DEFAULT '#{SystemActivity::SYSTEM_USER_ID}'::uuid,
      ALTER COLUMN modified_by SET DEFAULT '#{SystemActivity::SYSTEM_USER_ID}'::uuid;
    SQL

    # Backfill any existing nulls
    execute <<~SQL
      UPDATE system_activities
      SET created_by = COALESCE(created_by, '#{SystemActivity::SYSTEM_USER_ID}'::uuid),
          modified_by = COALESCE(modified_by, '#{SystemActivity::SYSTEM_USER_ID}'::uuid)
      WHERE created_by IS NULL OR modified_by IS NULL;
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE system_activities
      ALTER COLUMN created_by DROP DEFAULT,
      ALTER COLUMN modified_by DROP DEFAULT;
    SQL
  end
end
