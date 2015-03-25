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
    assert_equal nil, $polluted
  end
end
