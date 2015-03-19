name = "forking_test_runner"
require "./lib/#{name.gsub("-","/")}/version"

Gem::Specification.new name, ForkingTestRunner::VERSION do |s|
  s.summary = "Run every test in a fork to avoid pollution and get clean output per test"
  s.authors = ["Michael Grosser"]
  s.email = "michael@grosser.it"
  s.homepage = "https://github.com/grosser/#{name}"
  s.files = `git ls-files lib/ bin/ MIT-LICENSE`.split("\n")
  s.add_runtime_dependency "parallel_tests", "1.3.7"
  s.add_runtime_dependency "activerecord", "< 4.0.0"
  s.executables = ["forking-test-runner"]
  s.license = "MIT"
end
