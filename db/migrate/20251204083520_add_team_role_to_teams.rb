class AddTeamRoleToTeams < ActiveRecord::Migration[7.2]
  def change
    add_column :teams, :team_role, :string
  end
end
