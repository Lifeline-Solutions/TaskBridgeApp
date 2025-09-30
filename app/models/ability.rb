class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new # guest user (not logged in)
    if user.has_role? :admin
      can :manage, :all # allow super admins to do anything
      can :generate, :report

    elsif user.has_role? :observer
      can :read, :all
      can %i[generate report cease_fire_report email_report user_report breach_report user_report], :report
      can %i[add_status add_status update_issue_type update_due_date update_priority index_home all_tickets show_all_tickets_user_inactive all_tickets_created_by_inactive_team_members all_tickets_and_no_team_member],
          Ticket
      can :manage, Issue, user_id: user.id
      can %i[profiles_show profiles_show_user], :profiles

    elsif user.has_role? :hod
      can %i[read assign_user unassign_user add_team manage_users], Project
      can %i[create read assign_tag unassign_tag add_status update_issue_type update_due_date update_priority index_home all_tickets modal_show show_all_tickets_user_inactive all_tickets_created_by_inactive_team_members all_tickets_and_no_team_member],
          Ticket
      can %i[edit update], Ticket, user_id: user.id
      can :manage, Issue, user_id: user.id
      can %i[create read add_user remove_user edit update manage_users product_status download_tasks_csv], Product
      cannot %i[delete], Product
      can %i[create edit read], User, roles: { name: ['agent', 'client', 'project manager'] }
      cannot :manage, User, roles: { name: 'admin' }
      can :manage, Board
      can :manage, Task
      can :generate, :report
      can :manage, Team
      can %i[profiles_show profiles_show_user], :profiles

    elsif user.has_role? :ceo
      can :generate, :report # allow ceo to do anything cept manage all

    elsif user.has_role?('project manager')
      can %i[read assign_user unassign_user add_team manage_users], Project
      can %i[create read assign_tag unassign_tag add_status update_issue_type update_due_date update_priority index_home all_tickets modal_show],
          Ticket
      can %i[edit update], Ticket, user_id: user.id
      can :manage, Issue, user_id: user.id
      can %i[create read add_user remove_user edit update manage_users product_status download_tasks_csv], Product
      cannot %i[delete], Product
      can %i[create edit read], User, roles: { name: ['agent', 'client', 'project manager'] }
      cannot :manage, User, roles: { name: 'admin' }
      can :manage, Board
      can :manage, Task
      can :generate, :report
      can :manage, Team
      can %i[profiles_show profiles_show_user], :profiles

    elsif user.has_role? :agent
      can %i[read assign_user unassign_user add_team manage_users], Project
      can %i[create read assign_tag unassign_tag update_status add_status index_home all_tickets modal_show], Ticket
      can %i[edit update], Ticket, user_id: user.id
      can :manage, Issue, user_id: user.id
      can :update_due_date, Ticket
      cannot %i[create delete edit download_tasks_csv], Product
      cannot %i[create delete edit], Board
      can :read, Product
      can :read, Board
      can :read, Task
      can :manage, Message
      can %i[create edit update destroy], DefectMessage, user_id: user.id
      can :manage, Defect
      can :generate, :report
      can %i[profiles_show profiles_show_user], :profiles

    elsif user.has_role? :client
      can :read, Project
      can %i[create read assign_tag unassign_tag update_status add_status index_home all_tickets modal_show], Ticket
      can %i[edit update], Ticket, user_id: user.id
      can :manage, Issue, user_id: user.id
      cannot %i[create delete edit], Product
      can :read, Product
      cannot %i[create delete edit], Board
      cannot :manage, Task
      can :manage, Message
      can :generate, :report
      can %i[profiles_show profiles_show_user], :profiles

    elsif user.has_role? :qa
      can %i[create edit update destroy], DefectMessage, user_id: user.id

    else
      can :read, Project
      can :read, Ticket
      can :read, Issue
      can :read, User, user_id: user.id
      cannot :manage, Product
      cannot :manage, Board
      cannot :manage, Task
    end
  end
end
