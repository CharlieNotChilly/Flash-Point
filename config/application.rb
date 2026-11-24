require_relative "boot"
require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"

Bundler.require(*Rails.groups)

module Flashpoint
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true
    config.active_job.queue_adapter = :sidekiq
    config.eager_load = !Rails.env.local?
    config.logger = ActiveSupport::Logger.new($stdout)
  end
end
