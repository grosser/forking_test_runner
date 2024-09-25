# frozen_string_literal: true
require_relative "../test/test_helper"

class SimpleTest < ActiveSupport::TestCase
  2.times do |i|
    test "transaction #{i}" do
      assert_equal 1, User.count, 'fixtures not loaded'
      User.create!
      assert_equal 2, User.count
    end
  end

  test "pollution" do
    assert_nil $polluted
  end

  test "loading fixtures once" do
    assert_equal 1, $fixtures_loaded
  end
end
