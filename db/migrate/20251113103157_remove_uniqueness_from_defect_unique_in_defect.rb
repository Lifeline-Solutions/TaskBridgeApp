class RemoveUniquenessFromDefectUniqueInDefect < ActiveRecord::Migration[7.2]
  def change
    if index_exists?(:defects, :defect_unique, unique: true)
      remove_index :defects, name: "index_defects_on_defect_unique"
    end

    unless index_exists?(:defects, :defect_unique)
      add_index :defects, :defect_unique, unique: false
    end

  end
end
