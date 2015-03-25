require "bundler/setup"
require "bundler/gem_tasks"
require "bump/tasks"
require "wwtd/tasks"

task default: "wwtd:local"

task :spec do
  sh "rspec spec/"
end
