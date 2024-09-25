# frozen_string_literal: true

# otherwise blows up in some CI combinations
require "active_support" # TODO: we only need test_case, but that breaks CI with a weird issue
require "minitest/autorun"

# TODO: find out why this needs to be here
module ActiveSupport
  class << self
    attr_accessor :test_order
  end
end
ActiveSupport.test_order = :sorted

$test_env = ENV["TEST_ENV_NUMBER"]
