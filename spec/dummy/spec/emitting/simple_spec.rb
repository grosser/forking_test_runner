require "spec_helper"

describe "Foo" do
  class DummyClass
    def self.method_under_test
      STDERR.puts 'Warning: Code Under Test'
      true
    end
  end

  it { expect(DummyClass.method_under_test).to be true }
end
