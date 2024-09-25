# frozen_string_literal: true
require 'bundler/setup'
require 'active_record'

$LOAD_PATH << File.expand_path('lib', __dir__)

ENV["RAILS_ENV"] = "test"

# connect
configurations = {
  "test" => {
    adapter: "sqlite3",
    database: File.expand_path("../db#{ENV["FORCE_TEST_ENV_NUMBER"] || ENV["TEST_ENV_NUMBER"]}.sqlite", __FILE__)
  }
}
ActiveRecord::Base.configurations = { "test" => configurations }

ActiveRecord::Base.establish_connection :test

# create tables
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define(version: 1) do
  create_table :users, force: true do |t|
    t.string :name
  end
end

# create models ... also make sure that fixture loading is covered
autoload :User, 'user'

# Logging in case something is weird
# ActiveRecord::Base.logger = Logger.new(STDOUT)

require 'active_record/fixtures'

ActiveSupport::TestCase.include ActiveRecord::TestFixtures

# have to tell AS where to find fixtures or it looks into the the root directory ...
path = File.expand_path('fixtures', __dir__)
(if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
   ActiveSupport::TestCase.fixture_paths = [path]
 else
   ActiveSupport::TestCase.fixture_path = path
 end
) # TODO: remove after dropping rails 7,0 support
