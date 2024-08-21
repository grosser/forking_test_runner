# frozen_string_literal: true
require "bundler/setup"
require "forking_test_runner/version"
require "forking_test_runner"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :should }
  config.mock_with(:rspec) { |c| c.syntax = :should }
end
