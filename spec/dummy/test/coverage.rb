PreloadedCoverage.generate_coverage_after_fork
puts "preloaded: " + Coverage.result.fetch(File.expand_path("../preloaded.rb", __FILE__)).inspect
