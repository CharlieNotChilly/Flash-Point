ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort "Specs require the test environment" unless Rails.env.test?
require "rspec/rails"

ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.use_transactional_fixtures = true
end
