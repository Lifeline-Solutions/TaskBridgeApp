class CreateLabels < ActiveRecord::Migration[7.2]
   def change
    create_table :labels, id: :uuid do |t|
      t.string :name, null: false
      t.uuid :created_by
      t.uuid :modified_by
      t.uuid :deleted_by
      t.datetime :deleted_on
      t.timestamps
    end

    add_index :labels, :name
    # Case-insensitive uniqueness (Postgres specific expression index)
    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE UNIQUE INDEX index_labels_on_lower_name ON labels (LOWER(name));
        SQL
      end
      dir.down do
        execute 'DROP INDEX IF EXISTS index_labels_on_lower_name'
      end
    end
  end
end
