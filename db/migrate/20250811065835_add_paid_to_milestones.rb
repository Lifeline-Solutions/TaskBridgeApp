class AddPaidToMilestones < ActiveRecord::Migration[7.2]
  def change
    add_column :milestones, :paid, :boolean, default: false
  end
end
