class CreateDefectFailureReports < ActiveRecord::Migration[7.2]
  def change
    create_table :defect_failure_reports, id: :uuid do |t|
      t.uuid    :defect_id, null: false
      t.integer :retest_number, null: false
      t.datetime :captured_at, null: false

      # audit / soft delete / archive fields
      t.references :created_by,  type: :uuid, foreign_key: { to_table: :users }
      t.references :modified_by, type: :uuid, foreign_key: { to_table: :users }
      t.references :deleted_by,  type: :uuid, foreign_key: { to_table: :users }
      t.datetime :deleted_on

      t.boolean :archive_status, default: false, null: false

      t.timestamps
    end

    add_index :defect_failure_reports, :defect_id
    add_index :defect_failure_reports, :retest_number
    add_index :defect_failure_reports, :archive_status
    add_index :defect_failure_reports, :deleted_on

    # Foreign key to defects
    add_foreign_key :defect_failure_reports, :defects, column: :defect_id
  end
end
