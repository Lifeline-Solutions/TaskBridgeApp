# config/deploy/staging.rb

set :stage, :staging
set :rails_env, 'staging'                    # <- makes rake tasks use staging
set :branch, ENV.fetch('BRANCH', 'dev')

server '172.16.2.15', user: 'deploy', roles: %w[app db web]

# Where to deploy (adjust if you use a different path)
# set :deploy_to, "/home/deploy/#{fetch(:application)}-staging"
# or, if you share with prod but separate branches:
# set :deploy_to, '/home/deploy/CSPM'

# Link the env-specific credentials key (DO NOT commit this file)


# Usual shared directories
append :linked_dirs,
  'log',
  'tmp/pids',
  'tmp/cache',
  'tmp/sockets',
  'public/system',
  'storage' # if Active Storage local/disk in staging

# Ensure tasks that shell out also see RAILS_ENV=staging
set :default_env, {
  'RAILS_ENV' => 'staging',
  'SMTP_USERNAME' => 'cspm@craftsilicon.com',
  'SMTP_PASSWORD' => '#cspm@123#'
}

# Optional niceties
set :assets_roles, %i[web app]
set :keep_releases, 5
set :conditionally_migrate, true
