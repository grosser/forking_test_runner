require "spec_helper"

describe ForkingTestRunner do
  it "has a VERSION" do
    ForkingTestRunner::VERSION.should =~ /^[\.\da-z]+$/
  end
end
