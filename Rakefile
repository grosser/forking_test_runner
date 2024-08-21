# frozen_string_literal: true
require "bundler/setup"
require "bundler/gem_tasks"
require "bump/tasks"

# update readme before new change is committed
class << Bump::Bump
  prepend(
    Module.new do
      def replace(*)
        super
        file = "Readme.md"
        marker = "<!-- Updated by rake bump:patch -->\n"
        marker_rex = /#{Regexp.escape(marker)}.*#{Regexp.escape(marker)}/m
        usage = `./bin/forking-test-runner --help`
        raise "Failed to update readme" unless $?.success?
        usage_with_marker = "#{marker}```\n#{usage}```\n#{marker}"
        File.write(file, File.read(file).sub!(marker_rex, usage_with_marker) || raise("Unable to find #{marker.strip} in #{file}"))
        `git add #{file}`
      end
    end
  )
end

desc "Run tests"
task default: [:spec, :rubocop]

desc "Run tests"
task :spec do
  cmd = "bundle exec rspec spec/forking_test_runner_spec.rb"
  if ENV["CI"] # clearing env breaks CI but is needed locally
    sh cmd
  else
    Bundler.with_original_env { sh cmd }
  end
end

desc "Rubocop"
task :rubocop do
  sh "rubocop --parallel"
end

desc "Bundle all gemfiles"
task :bundle_all do
  cmd = ENV["CMD"]
  Bundler.with_original_env do
    Dir["gemfiles/*.gemfile"].each do |gemfile|
      sh "BUNDLE_GEMFILE=#{gemfile} bundle #{cmd}"
      sh "BUNDLE_GEMFILE=#{gemfile} bundle lock --add-platform x86_64-linux" # for github
    end
  end
end
