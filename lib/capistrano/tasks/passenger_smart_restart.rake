# lib/capistrano/tasks/passenger_smart_restart.rake

namespace :passenger do
  desc 'Smart restart for Phusion Passenger when multiple instances exist'
  task :restart do
    on roles(:app) do |host|
      # Resolve passenger and passenger-config paths on the remote host
      passenger_bin = begin
        capture(:which, 'passenger').strip
      rescue StandardError
        '/usr/bin/passenger'
      end
      passenger_config_bin = begin
        capture(:which, 'passenger-config').strip
      rescue StandardError
        '/usr/bin/passenger-config'
      end

      info "Passenger binary: #{passenger_bin}"
      info "Passenger-config binary: #{passenger_config_bin}"

      # Confirm passenger-config accepts the restart-app command
      begin
        help_output = capture(:bash, '-lc', "#{passenger_config_bin} --help 2>&1").to_s
      rescue StandardError => e
        warn "Could not run '#{passenger_config_bin} --help' on #{host}: #{e}"
        help_output = ''
      end

      unless help_output.include?('restart-app')
        warn "Warning: '#{passenger_config_bin}' on #{host} does not advertise 'restart-app' in --help output. Output:\n#{help_output}"
        # continue but be prepared to present a clearer error if the restart command fails
      end

      # Try to determine the passenger version (e.g. 'Phusion Passenger(R) 6.1.0')
      passenger_version_number = nil

      begin
        passenger_version_output = capture(:bash, '-lc', "#{passenger_bin} -v 2>&1").strip
        # extract a version like 6.1.0 or 6.0.24 (first occurrence of digit groups)
        passenger_version_number = passenger_version_output[/\d+\.\d+(?:\.\d+)?/]
        info "Detected passenger version on #{host}: #{passenger_version_number || passenger_version_output}"
      rescue StandardError => e
        warn "Could not determine passenger version on #{host}: #{e}"
      end

      # Try to list instances
      begin
        instances_output = capture(:bash, '-lc', "#{passenger_config_bin} list-instances 2>&1").strip
      rescue StandardError => e
        warn "passenger-config list-instances failed on #{host}: #{e}"
        instances_output = ''
      end

      # Count instances (skip header lines if present)
      instance_lines = instances_output.to_s.lines.map(&:chomp)
      instance_entries = instance_lines.drop_while { |l| l.strip == '' }
      # remove header (usually 2 lines) if present
      instance_entries = instance_entries.drop(2) if instance_entries.length > 2
      instance_count = instance_entries.count { |l| l.strip != '' }

      # Allow user to explicitly set the instance via server property, ENV, or Capistrano variable
      # server-specific property (preferred): server 'host', passenger_instance: 'NAME'
      server_prop = host.properties[:passenger_instance] if host.respond_to?(:properties)
      chosen_instance = ENV['PASSENGER_INSTANCE'] || server_prop || fetch(:passenger_instance, nil)

      if (chosen_instance.nil? || chosen_instance.empty?) && passenger_version_number && instances_output && !instances_output.empty?
        # Try to find an instance whose Description contains the detected passenger version
        begin
          chosen_instance = capture(:bash, '-lc', "#{passenger_config_bin} list-instances 2>/dev/null | awk -v v='#{passenger_version_number}' '$0 ~ v {print $1; exit}'").strip
        rescue StandardError
          chosen_instance = nil
        end
      end

      if (chosen_instance.nil? || chosen_instance.empty?) && instances_output && !instances_output.empty?
        # Fall back to the first listed instance (skip header lines)
        begin
          chosen_instance = capture(:bash, '-lc', "#{passenger_config_bin} list-instances 2>/dev/null | awk 'NR>2 {print $1; exit}'").strip
        rescue StandardError
          chosen_instance = nil
        end
      end

      # If multiple instances are present and we couldn't pick one, abort with instructions
      if (chosen_instance.nil? || chosen_instance.empty?) && instance_count > 1
        error_msg = <<~MSG
          Multiple Phusion Passenger instances detected on #{host} (#{instance_count} instances).
          Automatic selection failed. Please set the instance to target and re-run the deploy.

          Options:
            - Export PASSENGER_INSTANCE on your deploy machine, e.g.
                PASSENGER_INSTANCE=nxy2uUdT cap production deploy
            - Or set in your stage file (e.g. config/deploy/production.rb):
                set :passenger_instance, 'nxy2uUdT'
            - Or set per-server: server '172.17.40.11', user: 'deploy', roles: %w[app web db], passenger_instance: 'nxy2uUdT'

          To see the available instance names on the server run:
            passenger-config list-instances
        MSG
        raise SSHKit::Command::Failed, error_msg
      end

      # Build restart command
      app_path = fetch(:deploy_to)
      cmd = if chosen_instance && !chosen_instance.empty?
              "#{passenger_config_bin} restart-app #{app_path} --ignore-app-not-running --instance #{chosen_instance}"
            else
              "#{passenger_config_bin} restart-app #{app_path} --ignore-app-not-running"
            end

      begin
        info "Running: #{cmd} on #{host}"
        execute :bash, '-lc', cmd
      rescue SSHKit::Command::Failed => e
        # Provide a clearer error message including the original failure output (if available)
        raise SSHKit::Command::Failed, <<~ERR
          passenger-config restart failed on #{host}.
          Command: #{cmd}

          Original error: #{e.message}

          Common causes:
            - Multiple passenger instances exist but no --instance was given.
            - The passenger-config binary on the server is not the one expected.

          Troubleshooting steps:
            - SSH to the server and run 'passenger-config list-instances' to see available instances.
            - Run the restart command manually to inspect output:
                #{cmd}
            - If needed, set PASSENGER_INSTANCE or server property :passenger_instance and re-run deploy.
        ERR
      end
    end
  end
end
