namespace :smtp do
  desc 'Diagnose SMTP connectivity and authentication'
  task :diagnose do
    require 'net/smtp'
    require 'timeout'

    settings = ActionMailer::Base.smtp_settings

    puts "\n#{'=' * 80}"
    puts 'SMTP DIAGNOSTIC REPORT'
    puts '=' * 80
    puts "Timestamp: #{Time.now}"
    puts ''
    puts 'Current ActionMailer SMTP Settings:'
    puts "  Address:       #{settings[:address]}"
    puts "  Port:          #{settings[:port]}"
    puts "  Domain:        #{settings[:domain]}"
    puts "  Username:      #{settings[:user_name].present? ? '[SET]' : '[MISSING]'}"
    puts "  Password:      #{settings[:password].present? ? '[SET]' : '[MISSING]'}"
    puts "  Auth Method:   #{settings[:authentication]}"
    puts "  SSL:           #{settings[:ssl] ? 'true' : 'false'}"
    puts "  STARTTLS Auto: #{settings[:enable_starttls_auto] ? 'true' : 'false'}"
    puts "  Open Timeout:  #{settings[:open_timeout]} seconds"
    puts "  Read Timeout:  #{settings[:read_timeout]} seconds"
    puts ''

    # 1. DNS Resolution
    puts '-' * 80
    puts '1. DNS RESOLUTION TEST'
    puts '-' * 80
    begin
      host_ip = Socket.gethostbyname(settings[:address]).last.unpack('C*').join('.')
      puts "✓ DNS resolved #{settings[:address]} to #{host_ip}"
    rescue StandardError => e
      puts "✗ DNS resolution failed: #{e.class}: #{e.message}"
    end
    puts ''

    # 2. TCP Connectivity
    puts '-' * 80
    puts '2. TCP CONNECTIVITY TEST'
    puts '-' * 80
    begin
      Timeout.timeout(10) do
        socket = TCPSocket.new(settings[:address], settings[:port])
        socket.close
        puts "✓ TCP connection successful to #{settings[:address]}:#{settings[:port]}"
      end
    rescue Timeout::Error
      puts "✗ TCP connection timeout (#{settings[:port]})"
    rescue StandardError => e
      puts "✗ TCP connection failed: #{e.class}: #{e.message}"
    end
    puts ''

    # 3. TLS/SSL Handshake (basic)
    puts '-' * 80
    puts '3. TLS/SSL HANDSHAKE TEST'
    puts '-' * 80
    begin
      require 'openssl'
      context = OpenSSL::SSL::SSLContext.new
      context.verify_mode = OpenSSL::SSL::VERIFY_NONE

      if settings[:ssl]
        puts "Testing implicit SSL (port #{settings[:port]})..."
        socket = TCPSocket.new(settings[:address], settings[:port])
        ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, context)
        ssl_socket.connect
        puts '✓ SSL handshake successful'
        ssl_socket.close
      elsif settings[:enable_starttls_auto]
        puts "Testing STARTTLS (port #{settings[:port]})..."
        socket = TCPSocket.new(settings[:address], settings[:port])
        banner = socket.gets
        puts "  Server banner: #{banner.strip}"
        socket.puts 'EHLO localhost'
        socket.gets # EHLO response
        socket.puts 'STARTTLS'
        response = socket.gets
        if response.include?('220') || response.include?('250')
          ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, context)
          ssl_socket.connect
          puts '✓ STARTTLS handshake successful'
          ssl_socket.close
        else
          puts "✗ STARTTLS not advertised: #{response.strip}"
        end
      end
    rescue StandardError => e
      puts "✗ TLS handshake failed: #{e.class}: #{e.message}"
    end
    puts ''

    # 4. SMTP Authentication
    puts '-' * 80
    puts '4. SMTP AUTHENTICATION TEST'
    puts '-' * 80
    if settings[:user_name].blank? || settings[:password].blank?
      puts '✗ SMTP_USERNAME or SMTP_PASSWORD not set in ENV'
    else
      begin
        smtp = Net::SMTP.new(settings[:address], settings[:port])
        smtp.open_timeout = settings[:open_timeout] || 30
        smtp.read_timeout = settings[:read_timeout] || 30

        smtp.start(
          settings[:domain],
          settings[:user_name],
          settings[:password],
          settings[:authentication]
        ) do |_conn|
          puts '✓ SMTP authentication successful'
        end
      rescue Net::SMTPAuthenticationError => e
        puts "✗ SMTP authentication failed: #{e.message}"
        puts '  Check username/password and auth method'
      rescue Net::SMTPFatalError => e
        puts "✗ SMTP fatal error (relay rejection): #{e.message}"
        puts '  Server may be blocking your IP or refusing relay'
      rescue Timeout::Error => e
        puts "✗ SMTP timeout: #{e.message}"
      rescue StandardError => e
        puts "✗ SMTP error: #{e.class}: #{e.message}"
      end
    end
    puts ''

    # 5. Alternative Ports/Modes
    puts '-' * 80
    puts '5. TESTING ALTERNATIVE PORTS'
    puts '-' * 80
    [465, 587, 25, 2525].each do |test_port|
      next if test_port == settings[:port]

      begin
        Timeout.timeout(5) do
          socket = TCPSocket.new(settings[:address], test_port)
          banner = socket.gets
          socket.close
          puts "✓ Port #{test_port} is open (banner: #{banner.strip[0..50]}...)"
        end
      rescue Timeout::Error
        puts "⊘ Port #{test_port} timeout"
      rescue StandardError => _e
        puts "✗ Port #{test_port} not reachable"
      end
    end
    puts ''

    puts '=' * 80
    puts 'RECOMMENDATIONS:'
    puts '=' * 80
    if settings[:port] == 465
      puts '• Port 465 requires implicit SSL. Ensure SMTP_USE_SSL=true'
    elsif settings[:port] == 587
      puts '• Port 587 requires STARTTLS. Ensure SMTP_ENABLE_STARTTLS_AUTO=true'
    end
    puts '• If 554 persists, contact your SMTP provider to:'
    puts '  - Allow-list your server IP'
    puts '  - Confirm relay is accepting connections'
    puts '  - Verify username/password and authentication method'
    puts ''
  end
end
