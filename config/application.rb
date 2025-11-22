require_relative "boot"

require "rails/all"
require 'paper_trail'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Cspm
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1
    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))
    config.time_zone = 'Africa/Nairobi'

    config.active_record.default_timezone = :utc
    config.autoload_paths  << Rails.root.join('app', 'middleware')
    config.eager_load_paths << Rails.root.join('app', 'middleware')
    config.middleware.insert_before 0, ErrorNotifierMiddleware

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.active_storage.variant_processor = :mini_magick
    config.active_job.queue_adapter = :sidekiq

    config.active_storage.queues.analysis = :active_storage_analysis
    config.active_storage.queues.purge = :active_storage_purge
    config.active_storage.service_urls_expire_in = 5.minutes
    config.active_storage.service = :local

  end
end
