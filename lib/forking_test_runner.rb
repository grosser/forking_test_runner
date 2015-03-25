module ForkingTestRunner
  class << self
    def cli(argv)
      disable_minitest_autorun
      load_test_env(delete_argv("--helper", argv))

      runtime_log = delete_argv("--runtime-log", argv)
      tests = find_tests_for_group(argv, runtime_log)
      puts "Running tests #{tests.map(&:first).join(" ")}"

      show_time = tests[0][1]

      clear = "------"
      results = tests.map do |file, expected|
        puts "#{clear} >>> #{file}"
        success = false
        time = Benchmark.realtime do
          success = run_test(file)
        end
        puts "Time: expected #{expected.round(2)}, actual #{time.round(2)}" if show_time
        puts "#{clear} <<< #{file} ---- #{success ? "OK" : "Failed"}"
        [file, time, expected, success]
      end

      puts "\nResults:"
      puts results.map { |f,_,_,r| "#{f}: #{r ? "OK" : "Fail"}"}

      if show_time
        puts "Time: #{results.map { |_,time,expected,_| time - expected }.inject(:+).to_f.round(2)} diff to expected"
      end

      # log runtime and then curl it into the runtime log location
      if ENV["RECORD_RUNTIME"]
        require 'tempfile'
        slug = ENV.fetch("TRAVIS_REPO_SLUG").sub("/", "-")
        id = ENV.fetch("TRAVIS_BUILD_NUMBER")
        url = "https://amend.herokuapp.com/amend/#{slug}-#{id}"
        data = results.map { |f,time,_,_| "#{f}:#{time.round(2)}" }.join("\n") << "\n"
        Tempfile.open("runtime.log") do |f|
          f.write(data)
          f.close
          result = `curl -X POST --data-binary @#{f.path} #{url}`
          puts "amended runtime log\ncurl #{url} | sort > #{runtime_log}\nStatus: #{$?.success?}\nResponse: #{result}"
        end
      end

      results.map(&:last).all? ? 0 : 1
    end

    private

    def load_test_env(helper=nil)
      helper = helper || "test/test_helper"
      require "./#{helper}"
    end

    # This forces Rails to load all fixtures, then prevents it from
    # "deleting and re-inserting all fixtures" when a new connection is used (forked).
    def preload_fixtures
      return if @preloaded
      @preloaded = true

      fixtures = (ActiveSupport::VERSION::MAJOR == 3 ? ActiveRecord::Fixtures : ActiveRecord::FixtureSet)

      # reuse our pre-loaded fixtures even if we have a different connection
      fixtures.send(:define_method, :cache_for_connection) do |_connection|
        fixtures.class_variable_get(:@@all_cached_fixtures)[:unique]
      end

      ActiveSupport::TestCase.fixtures :all

      fixtures.create_fixtures(
        ActiveSupport::TestCase.fixture_path,
        ActiveSupport::TestCase.fixture_table_names,
        ActiveSupport::TestCase.fixture_class_names
      )
    end

    # don't let minitest setup another exit hook
    def disable_minitest_autorun
      toggle_minitest_autorun false
    end

    def enable_minitest_autorun
      toggle_minitest_autorun true
    end

    def run_test(file)
      preload_fixtures
      ActiveRecord::Base.connection.disconnect!
      child = fork do
        key = (ActiveRecord::VERSION::STRING >= "4.1.0" ? :test : "test")
        ActiveRecord::Base.establish_connection key
        enable_minitest_autorun
        require "./#{file}"
      end
      Process.wait(child)
      $?.success?
    end

    def find_tests_for_group(argv, runtime_log)
      require 'parallel_tests/test/runner'

      if argv.include?("--group")
        # delete options we want while leaving others as they are (-v / --seed etc)
        group, number_of_groups = ['--group', '--groups'].map do |arg|
          value = delete_argv(arg, argv) || raise("Did not find option #{arg}")
          value.to_i
        end
        dir = ARGV.shift
        raise "Unable to find directory #{dir.inspect}" unless File.exist?(dir.to_s)
        tests = [dir]
      else
        group = 1
        number_of_groups = 1
        size = argv.index("--") || argv.size
        tests = argv.slice!(0, size)
        argv.shift # remove --
      end

      group_by = (runtime_log ? :runtime : :filesize)
      tests = ParallelTests::Test::Runner.send(:tests_with_size, tests, runtime_log: runtime_log, group_by: group_by)
      groups = ParallelTests::Grouper.in_even_groups_by_size(tests, number_of_groups, {})
      group = groups[group - 1] || raise("Group #{group} not found")

      # return tests with runtime
      tests = Hash[tests]
      group.map { |test| [test, (tests[test] if group_by == :runtime)] }
    end

    def delete_argv(arg, argv)
      return unless index = argv.index(arg)
      argv.delete_at(index)
      argv.delete_at(index)
    end

    def toggle_minitest_autorun(value)
      klass = begin
        require 'minitest/unit' # only exists on 4
        MiniTest::Unit
      rescue LoadError
        require 'minitest/test' # exists on 5 and 4 with minitest-rails
        Minitest
      end
      klass.class_variable_set("@@installed_at_exit", !value)
      klass.autorun if value
    end
  end
end
