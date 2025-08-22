class AddIssueTypeToDefects < ActiveRecord::Migration[7.2]
  def change
    add_column :defects, :issue_type, :string, default: 'Bug'
  end
end
