# frozen_string_literal: true
if ENV["COVERAGE"]
  require 'coverage'
  if ENV["COVERAGE"] == "branches"
    Coverage.start lines: true, branches: true
  else
    Coverage.start
  end
  require_relative 'preloaded'
  PreloadedCoverage.generate_coverage_before_fork
end

require_relative "../setup_test_model"
require_relative "no_ar_helper"

if ENV.key?("DUMMY_SPEC_CALLBACK_FILE")
  ForkingTestRunner.before_fork_callbacks << proc do
    File.open(ENV["DUMMY_SPEC_CALLBACK_FILE"], 'a') do |f|
      f.write "before_fork_called\n"
    end
  end
  ForkingTestRunner.after_fork_callbacks << proc do
    File.open(ENV["DUMMY_SPEC_CALLBACK_FILE"], 'a') do |f|
      f.write "after_fork_called\n"
    end
  end
end
