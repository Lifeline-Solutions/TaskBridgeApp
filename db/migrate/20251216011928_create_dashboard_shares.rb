class CreateDashboardShares < ActiveRecord::Migration[7.2]
  def change
    create_table :dashboard_shares, id: :uuid do |t|
      t.references :dashboard, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end
  end
end
