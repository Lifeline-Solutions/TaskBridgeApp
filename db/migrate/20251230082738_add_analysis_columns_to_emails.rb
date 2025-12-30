class AddAnalysisColumnsToEmails < ActiveRecord::Migration[7.2]
  def change
    add_column :emails, :retried_at, :datetime
    add_column :emails, :retried_count, :integer, default: 0
    add_column :emails, :sent_at, :datetime
    add_column :emails, :failed_at, :datetime
    add_column :emails, :failed_count, :integer, default: 0
  end
end
