Sidekiq.configure_server do |config|
  config.redis = { url: 'redis://:your_password@localhost:6379/0' }
end



Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://:your_password@localhost:6379/0' }
end



ENV['SMTP_USERNAME'] ||= 'cspm@craftsilicon.com'
ENV['SMTP_PASSWORD'] ||= 'Cspm@2025!'

