# frozen_string_literal: true
require_relative "../test/no_ar_helper"

class NoArTest < ActiveSupport::TestCase
  test "runs" do
    puts "AR IS #{defined?(ActiveRecord::Base) || "UNDEFINED"}"
    assert true
  end
end
