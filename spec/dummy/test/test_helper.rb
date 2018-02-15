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
