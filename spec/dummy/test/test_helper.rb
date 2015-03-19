require 'bundler/setup'
require 'minitest/autorun'
require_relative 'setup_test_model'
require 'active_record/fixtures'

ActiveSupport::TestCase.include ActiveRecord::TestFixtures

# have to tell AS where to find fixtures or it looks into the the root directory ...
ActiveSupport::TestCase.fixture_path = File.expand_path("../fixtures", __FILE__)

class << ActiveSupport::TestCase
  # we cannot load the models for our fixtures
  def self.try_to_load_dependency(file)
  end
end
