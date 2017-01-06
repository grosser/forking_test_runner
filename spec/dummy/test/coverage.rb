PreloadedCoverage.generate_coverage_after_fork
result = Coverage.result
user = result.fetch(File.expand_path('../../lib/user.rb', __FILE__))
preloaded = result.fetch(File.expand_path("../preloaded.rb", __FILE__))
puts "user: #{user.inspect} preloaded: #{preloaded.inspect}"
