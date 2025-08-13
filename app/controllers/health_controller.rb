class HealthController < ApplicationController
  before_action :authenticate_user!
  def index
    checks = {}
    checks[:redis] = begin
      require 'redis'
      Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379')).ping == 'PONG'
    rescue StandardError => e
      "DOWN: #{e.class} #{e.message}"
    end

    checks[:smtp] = begin
      Net::SMTP.start(
        ENV.fetch('SMTP_ADDRESS', 'smtp.yourhost.tld'),
        ENV.fetch('SMTP_PORT', 587)
      ) { :ok }
      true
    rescue StandardError => e
      "DOWN: #{e.class} #{e.message}"
    end

    render json: { status: 'ok', time: Time.current, checks: checks }
  end
end
