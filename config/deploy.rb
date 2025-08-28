# config valid for current version and patch releases of Capistrano
lock "~> 3.19.1"

set :application, "CSPM"
set :repo_url, "ssh://git@devopsuat.craftsilicon.com:22/TaskBridge/TaskBridge/_git/TaskBridge"
set :branch, 'dev'

# Default branch is :master
# ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp

# Default deploy_to directory is /var/www/my_app_name
set :deploy_to, "/home/deploy/#{fetch(:application)}"

# Default value for :format is :airbrussh.
# set :format, :airbrussh

# You can configure the Airbrussh format using :format_options.
# These are the defaults.
# set :format_options, command_output: true, log_file: "log/capistrano.log", color: :auto, truncate: :auto

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
append :linked_files, "config/database.yml", "config/master.key"

# Default value for linked_dirs is []

append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "vendor/bundle", "public/system", "public/uploads", "storage"

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# config/deploy.rb

# Default value for local_user is ENV['USER']
# set :local_user, -> { `git config user.name`.chomp }

# Default value for keep_releases is 5
set :keep_releases, 5

# Uncomment the following to require manually verifying the host key before first deploy.
# set :ssh_options, verify_host_key: :secure

# Path on your local repo to the ERB template above
set :maintenance_template_path, File.expand_path('templates/maintenance.html.erb', __dir__)

# Where the generated maintenance.html will live on the server
# (served via public/system symlink)
set :maintenance_dir, -> { File.join(shared_path, 'system') }

# Optional but nice: show your app name in the page
set :application, 'CSPM' unless fetch(:application, nil)

# Make sure public/system is a shared (linked) dir so Nginx can find the file
set :linked_dirs, fetch(:linked_dirs, []) | %w[log tmp/pids tmp/cache tmp/sockets vendor/bundle public/system storage]

