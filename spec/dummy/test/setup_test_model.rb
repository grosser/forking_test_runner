require 'active_record'

# connect
ActiveRecord::Base.configurations = {
  "test" => {
    :adapter => "sqlite3",
    :database => File.expand_path("../db.sqlite", __FILE__)
  }
}

key = (ActiveRecord::VERSION::STRING >= "4.1.0" ? :test : "test")
ActiveRecord::Base.establish_connection key

# create tables
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define(:version => 1) do
  create_table :users, force: true do |t|
    t.string :name
  end
end

# create models
class User < ActiveRecord::Base
end

# Logging in case something is weird
# ActiveRecord::Base.logger = Logger.new(STDOUT)
