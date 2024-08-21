# frozen_string_literal: true
require "spec_helper"

describe "Foo" do
  class DummyClass # rubocop:disable Lint/ConstantDefinitionInBlock TODO define via lambda
    def self.method_under_test
      warn 'Warning: Code Under Test'
      true
    end
  end

  it { expect(DummyClass.method_under_test).to be true }
end
