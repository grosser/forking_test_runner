require "bundler/setup"
require "bundler/gem_tasks"
require "bump/tasks"
require "wwtd/tasks"

# update readme before new change is committed
class << Bump::Bump
  prepend(Module.new do
    def replace(*)
      super
      file = "Readme.md"
      marker = "<!-- Updated by rake bump:patch -->\n"
      marker_rex = /#{Regexp.escape(marker)}.*#{Regexp.escape(marker)}/m
      usage = `./bin/forking-test-runner --help`
      raise "Failed to update readme"  unless $?.success?
      usage_with_marker = "#{marker}```\n#{usage}```\n#{marker}"
      File.write(file, File.read(file).sub!(marker_rex, usage_with_marker) || raise("Unable to find #{marker.strip} in #{file}"))
      `git add #{file}`
    end
  end)
end

desc "Run tests"
task default: :spec

desc "Run tests"
task :spec do
  sh "bundle exec rspec spec/forking_test_runner_spec.rb"
end
