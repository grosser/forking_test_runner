# frozen_string_literal: true
require_relative "../test/no_ar_helper"

class FailTest < ActiveSupport::TestCase
  test "runs" do
    assert false
  end
end
