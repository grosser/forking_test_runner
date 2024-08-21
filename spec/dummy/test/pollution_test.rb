# frozen_string_literal: true
require_relative "../test/test_helper"

class PollutionTest < ActiveSupport::TestCase
  test "pollute" do
    $polluted = true
  end

  test "fails" do
    refute ENV["FAIL_NOW"]
  end
end
