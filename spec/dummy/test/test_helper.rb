if ENV["COVERAGE"]
  require 'coverage'
  Coverage.start
  require_relative 'preloaded'
  PreloadedCoverage.generate_coverage_before_fork
end

require_relative "../setup_test_model"
require_relative "no_ar_helper"
