require_relative "../test/test_helper"

class SimpleTest < ActiveSupport::TestCase
  2.times do |i|
    test "transaction #{i}" do
      User.count.must_equal 1, 'fixtures not loaded'
      User.create!
      User.count.must_equal 2
    end
  end

  test "pollution" do
    $polluted.must_equal nil
  end
end
