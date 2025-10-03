class AddAssignedUserToEvents < ActiveRecord::Migration[7.2]
  def change
    add_reference :events, :assigned_user, foreign_key: { to_table: :users }, type: :uuid
  end
end
