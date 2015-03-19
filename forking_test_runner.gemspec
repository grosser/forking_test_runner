name = "forking_test_runner"
require "./lib/#{name.gsub("-","/")}/version"

Gem::Specification.new name, ForkingTestRunner::VERSION do |s|
  s.summary = "Run every test in a fork to avoid pollution and get clean output per test"
  s.authors = ["Michael Grosser"]
  s.email = "michael@grosser.it"
  s.homepage = "https://github.com/grosser/#{name}"
  s.files = `git ls-files lib/ bin/ MIT-LICENSE`.split("\n")
  s.license = "MIT"
end
