require 'coverage'
require 'active_model'
require 'active_record'

Coverage.start

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

Coverage.result

Process.wait(
  fork do
    Coverage.start
    ActiveRecord::Base.connection.execute('select 1')
    puts Coverage.result
  end
)
