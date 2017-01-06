require 'bundler/setup'
require 'active_record'

$LOAD_PATH << File.expand_path('../lib', __FILE__)

# connect
ActiveRecord::Base.configurations = {
  "test" => {
    adapter: "sqlite3",
    database: File.expand_path("../db.sqlite", __FILE__)
  }
}

key = (ActiveRecord::VERSION::STRING >= "4.1.0" ? :test : "test")
ActiveRecord::Base.establish_connection key

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

ActiveSupport::TestCase.send(:include, ActiveRecord::TestFixtures)

# have to tell AS where to find fixtures or it looks into the the root directory ...
ActiveSupport::TestCase.fixture_path = File.expand_path("../fixtures", __FILE__)
