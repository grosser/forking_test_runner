require_relative "../test/no_ar_helper"

module ActiveSupport
  class << self
    attr_accessor :test_order
  end
end

class NoArTest < ActiveSupport::TestCase
  test "runs" do
    puts "AR IS #{defined?(ActiveRecord::Base) || "UNDEFINED"}"
    assert true
  end
end
