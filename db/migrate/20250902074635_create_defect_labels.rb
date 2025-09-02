class CreateDefectLabels < ActiveRecord::Migration[7.2]
  def change
    create_table :defect_labels, id: :uuid do |t|
      t.uuid :defect_id, null: false
      t.uuid :label_id, null: false
      t.uuid :created_by
      t.uuid :modified_by
      t.uuid :deleted_by
      t.datetime :deleted_on
      t.timestamps
    end

    add_index :defect_labels, :defect_id
    add_index :defect_labels, :label_id
    add_index :defect_labels, [:defect_id, :label_id], unique: true
  end
end
