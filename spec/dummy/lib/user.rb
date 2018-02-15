class User < ActiveRecord::Base
  def self.coverage_test
    rand if $flip_coverage_test == 1
  end
end
