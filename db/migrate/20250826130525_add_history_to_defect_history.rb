class AddHistoryToDefectHistory < ActiveRecord::Migration[7.2]
  def change
    add_column :defect_histories, :history, :string
  end
end
