# frozen_string_literal: true

# if you see "deprecator", enable this line, errors otherwise blows up in some CI combinations
# require "active_support"

require "active_support/test_case"
require "minitest/autorun"

# TODO: find out why this needs to be here
module ActiveSupport
  class << self
    attr_accessor :test_order
  end
end
ActiveSupport.test_order = :sorted

$test_env = ENV["TEST_ENV_NUMBER"]
