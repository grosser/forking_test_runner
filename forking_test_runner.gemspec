# frozen_string_literal: true
name = "forking_test_runner"
require "./lib/#{name.gsub("-", "/")}/version"

Gem::Specification.new name, ForkingTestRunner::VERSION do |s|
  s.summary = "Run every test in a fork to avoid pollution and get clean output per test"
  s.authors = ["Michael Grosser"]
  s.email = "michael@grosser.it"
  s.homepage = "https://github.com/grosser/#{name}"
  s.files = `git ls-files lib/ bin/ MIT-LICENSE`.split("\n")
  s.add_dependency "benchmark", ">= 0.5.0"
  s.add_dependency "parallel_tests", ">= 1.3.7"
  s.add_development_dependency "bump"
  s.add_development_dependency "bundler"
  s.add_development_dependency "drb"
  s.add_development_dependency "logger"
  s.add_development_dependency "minitest", "~> 5.0"
  s.add_development_dependency "mutex_m"
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec"
  s.add_development_dependency "rubocop", "~> 1.66.1" # lock version so we don't get new cops added
  s.add_development_dependency "sqlite3", "~> 1.4"
  s.required_ruby_version = ">= 3.2.0"

  s.executables = ["forking-test-runner"]
  s.license = "MIT"
end
