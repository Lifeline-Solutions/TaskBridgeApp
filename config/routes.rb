Rails.application.routes.draw do
  resources :sales, only: [:index]

  get 'users/active', to: 'users#active', as: 'active_users'
  get 'users/client_active', to: 'users#client_active', as: 'active_client_users'
  get 'users/manager_active', to: 'users#manager_active', as: 'active_manager_users'
  get 'users/agent_active', to: 'users#agent_active', as: 'active_agent_users'
  get "/crash", to: "test#crash"
  get '/health', to: 'health#index'

  devise_for :users, controllers: { invitations: 'invitations' }
  resources :users do
    collection do
      get :search
    end
    member do
      patch :status
    end
  end

  require 'sidekiq/web'
  authenticate :user, ->(user) { user.has_role?(:admin) } do
    mount Sidekiq::Web => '/sidekiq'
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # These Ids will be used when a user clicks on prepopulate clients drop down
  get '/commonly_selected_clients/ids', to: 'commonly_selected_clients#ids'
  resources :commonly_selected_clients, only: [:index, :create] do
    collection do
      delete :remove_client
    end
  end


  get 'cease_fire_report', to: 'data_center#cease_fire_report', as: 'cease_fire_report'
  get 'email_report', to: 'data_center#email_report'
  get 'daily_report', to: 'data_center#daily_report', as: 'daily_report'
  get 'send_team_ticket_emails', to: 'data_center#send_team_ticket_emails', as: 'send_team_ticket_emails'
  get 'breach_report', to: 'data_center#breach_report', as: 'breach_report'
  get 'user_report', to: 'data_center#user_report', as: 'user_report'
  get 'project_report', to: 'data_center#project_report', as: 'project_report'
  get 'daily_summary_report', to: 'data_center#daily_summary_report', as: 'daily_summary_report'
  get 'orm_report', to: 'data_center#orm_report', as: 'orm_report'
  get 'orm_team_report', to: 'data_center#orm_team_report', as: 'orm_team_report'
  get 'sod_report', to: 'data_center#sod_report', as: 'sod_report'
  get 'assigned_tickets', to: 'data_center#assigned_tickets', as: 'assigned_tickets'
  get 'user_report_view', to: 'data_center#user_report_view', as: 'user_report_view'
  get 'cbk_groupware_report', to: 'data_center#cbk_groupware_report', as: 'cbk_groupware_report'

  get 'dashboard', to: 'dashboards#index'
  get 'dashboards/fetch_stats', to: 'dashboards#fetch_stats'
  get 'dashboards/tickets', to: 'dashboards#tickets'

  root "home#index"
  get "home/index"

  resources :project do
    get 'project/:project_id/manage_users', to: 'project#manage_users', as: :project_manage_users
    member do
      post :assign_user
      delete :unassign_user
      post :add_team
      delete :remove_team
    end
    resources :tickets do
      collection do
        # all tickets special for home page
        get 'all_tickets'
        get 'closed_tickets_one_week'
        get 'created_tickets_one_week'
        get 'all_open_tickets'
        get 'non_breached_sla_tickets'
      end
      member do
        get :modal_show
        post :assign_tag
        delete :unassign_tag
        post :add_status
        patch :update_due_date
        patch :update_priority
        patch :update_issue_type
      end
      resources :issues
      resources :comments
      resources :ratings, only: :create
    end
  end
  
  resources :product do
    member do
      post :add_user
      delete :remove_user
      post :product_status
    end
    resources :tasks do
      member do
        post :assign_user
        delete :remove_task
        post :add_state
        delete :remove_state
      end
    end
  end

  resources :defect do
    member do
      post :add_defect
      delete :remove_defect
    end
    resources :bugs do
      member do
        post :add_bug
        delete :remove_bug
        post :bug_status
      end
    end
  end

  resources :projects, controller: 'project' do
    member do
      get :manage_users
    end
    resources :groupwares, only: :index
  end
  resources :product do
    member do
      get :manage_users
      post :add_user
      delete :remove_user
    end
    resources :groupwares do
      collection do
        get 'show_product_groupware', to: 'groupwares#show_product_groupware'
      end
      member do
        get 'show_index', to: 'scripts#show_index'
      end
    end
  end

  resources :software do
    resources :groupwares do
      resources :scripts

    end # Nested groupwares if needed in the context of software
  end

  resources :tasks do
    resources :messages
  end

  resources :notifications, only: [:index] do
    member do
      patch :mark_as_read
    end
  end

  resources :groupwares # Independent route for AJAX requests

  resources :milestones, only: [] do
    patch :toggle_paid, on: :member
  end
  
  resources :client
  resources :status
  resources :team do
    member do
      get "show_team_member"
    end
  end
  resources :location
end