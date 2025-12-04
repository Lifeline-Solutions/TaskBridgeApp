#!/usr/bin/env ruby
# SMTP Configuration Verification Script
# Usage: rails runner scripts/verify_smtp_config.rb

puts '=' * 80
puts 'SMTP CONFIGURATION VERIFICATION'
puts '=' * 80
puts ''

environments = %w[development staging production]

environments.each do |env_name|
  puts "Environment: #{env_name.upcase}"
  puts '-' * 80

  config_file = "config/environments/#{env_name}.rb"

  unless File.exist?(config_file)
    puts "  ⚠️  Config file not found: #{config_file}"
    puts ''
    next
  end

  content = File.read(config_file)

  # Extract SMTP settings block
  if content =~ /smtp_settings\s*=\s*\{([^}]+)\}/m
    smtp_block = Regexp.last_match(1)

    # Remove comments to avoid false positives
    smtp_block_no_comments = smtp_block.gsub(/#.*$/, '')

    has_ssl = smtp_block_no_comments.include?('ssl:')
    has_tls = smtp_block_no_comments.include?('tls:')
    has_starttls = smtp_block_no_comments.include?('enable_starttls_auto:')

    # Extract port if present
    port = nil
    if smtp_block =~ /port:\s*(\d+)/
      port = Regexp.last_match(1).to_i
    elsif smtp_block =~ /port:\s*(\w+)/
      port = "(variable: #{Regexp.last_match(1)})"
    end

    puts "  Port: #{port || 'not specified'}"
    puts "  SSL setting: #{has_ssl ? '✓ present' : '✗ not set'}"
    puts "  TLS setting: #{has_tls ? '✓ present' : '✗ not set'}"
    puts "  STARTTLS setting: #{has_starttls ? '✓ present' : '✗ not set'}"
    puts ''

    # Check for conflicts
    conflicts = []

    conflicts << "Both 'ssl' and 'tls' are set (redundant)" if has_ssl && has_tls

    if (has_ssl || has_tls) && has_starttls
      # Check if it's conditional (staging pattern)
      if smtp_block_no_comments =~ /ssl:\s*\([^)]+\)/ # Conditional ssl
        puts '  ✅ Conditional SSL/STARTTLS configuration detected (staging pattern)'
      else
        conflicts << 'Both SSL/TLS and STARTTLS are set (mutually exclusive!)'
      end
    end

    if port.is_a?(Integer)
      if port == 465
        conflicts << 'Port 465 requires ssl: true or tls: true' if !has_ssl && !has_tls
        if has_starttls && smtp_block_no_comments !~ /enable_starttls_auto:\s*\([^)]+\)/
          # Check if conditional
          conflicts << 'Port 465 should NOT have enable_starttls_auto (use ssl: true)'
        end
      elsif port == 587
        if (has_ssl || has_tls) && smtp_block_no_comments !~ /ssl:\s*\([^)]+\)/
          # Check if conditional
          conflicts << 'Port 587 should NOT have ssl/tls (use enable_starttls_auto: true)'
        end
        conflicts << 'Port 587 requires enable_starttls_auto: true' unless has_starttls
      end
    end

    if conflicts.any?
      puts '  ❌ ISSUES FOUND:'
      conflicts.each do |conflict|
        puts "     • #{conflict}"
      end
    else
      puts '  ✅ Configuration looks correct!'
    end
  else
    puts "  ⚠️  No smtp_settings found in #{config_file}"
  end

  puts ''
end

puts '=' * 80
puts 'RECOMMENDATIONS'
puts '=' * 80
puts ''
puts 'Port 465 (SMTPS - Implicit SSL):'
puts '  ssl: true'
puts '  # DO NOT set enable_starttls_auto'
puts ''
puts 'Port 587 (SMTP with STARTTLS - Explicit TLS):'
puts '  enable_starttls_auto: true'
puts '  # DO NOT set ssl or tls'
puts ''
puts 'Dynamic (Recommended):'
puts '  ssl: (smtp_port == 465)'
puts '  enable_starttls_auto: (smtp_port == 587)'
puts ''
puts '=' * 80
puts 'See SMTP_CONFIG_FIX.md for detailed documentation'
puts '=' * 80
