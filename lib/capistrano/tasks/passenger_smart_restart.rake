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

      # Allow user to explicitly set the instance via ENV or Capistrano variable
      chosen_instance = ENV['PASSENGER_INSTANCE'] || fetch(:passenger_instance, nil)

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

      # Build restart command
      app_path = fetch(:deploy_to)
      if chosen_instance && !chosen_instance.empty?
        info "Using passenger instance '#{chosen_instance}' to restart app on #{host}"
        execute :bash, '-lc', "#{passenger_config_bin} restart-app #{app_path} --ignore-app-not-running --instance #{chosen_instance}"
      else
        warn "No passenger instance selected on #{host}. Running restart without --instance (may fail if multiple instances are present)."
        execute :bash, '-lc', "#{passenger_config_bin} restart-app #{app_path} --ignore-app-not-running"
      end
    end
  end
end
