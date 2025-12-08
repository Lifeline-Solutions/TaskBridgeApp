class AddIdToDefectsUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :defects_users, :id, :uuid, default: "gen_random_uuid()", null: false, primary_key: true
  end
end
