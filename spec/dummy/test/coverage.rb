# frozen_string_literal: true
PreloadedCoverage.generate_coverage_after_fork
result = Coverage.result
user = result.fetch(File.expand_path('../lib/user.rb', __dir__))
preloaded = result.fetch(File.expand_path('preloaded.rb', __dir__))
puts "user: #{user.inspect} preloaded: #{preloaded.inspect}"
