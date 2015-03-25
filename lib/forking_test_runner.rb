module ForkingTestRunner
  CLEAR = "------"

  class << self
    def cli(argv)
      disable_minitest_autorun
      load_test_env(delete_argv("--helper", argv))

      # figure out what we need to run
      record_runtime = delete_argv("--record-runtime", argv)
      runtime_log = delete_argv("--runtime-log", argv)
      group, group_count, tests = extract_group_args(argv)
      tests = find_tests_for_group(group, group_count, tests, runtime_log)
      puts "Running tests #{tests.map(&:first).join(" ")}"

      # run all the tests
      results = tests.map do |file, expected|
        puts "#{CLEAR} >>> #{file}"
        time, success = benchmark { run_test(file) }
        puts "Time: expected #{expected.round(2)}, actual #{time.round(2)}" if runtime_log
        puts "#{CLEAR} <<< #{file} ---- #{success ? "OK" : "Failed"}"
        [file, time, expected, success]
      end

      # pretty print the results
      puts "\nResults:"
      puts results.map { |f,_,_,r| "#{f}: #{r ? "OK" : "Fail"}"}

      if runtime_log
        # show how long they ran vs expected
        diff = results.map { |_,time,expected,_| time - expected }.inject(:+).to_f
        puts "Time: #{diff.round(2)} diff to expected"
      end

      if record_runtime
        # store runtime log
        log = runtime_log || 'runtime.log'
        record_test_runtime(record_runtime, results, log)
      end

      # exit with success or failure
      results.map(&:last).all? ? 0 : 1
    end

    private

    def benchmark
      result = false
      time = Benchmark.realtime do
        result = yield
      end
      return time, result
    end

    # log runtime via dumping or curling it into the runtime log location
    def record_test_runtime(mode, results, log)
      data = results.map { |test, time| "#{test}:#{time.round(2)}" }.join("\n") << "\n"

      case mode
      when 'simple'
        File.write(log, data)
      when 'amend'
        slug = ENV.fetch("TRAVIS_REPO_SLUG").sub("/", "-")
        id = ENV.fetch("TRAVIS_BUILD_NUMBER")
        url = "https://amend.herokuapp.com/amend/#{slug}-#{id}"

        require 'tempfile'
        Tempfile.open("runtime.log") do |f|
          f.write(data)
          f.close
          result = `curl -X POST --data-binary @#{f.path} #{url}`
          puts "amended runtime log\ncurl #{url} | sort > #{log}\nStatus: #{$?.success?}\nResponse: #{result}"
        end
      else
        raise "Unsupported record-runtime flag: #{mode}"
      end
    end

    def extract_group_args(argv)
      if argv.include?("--group")
        # delete options we want while leaving others as they are (-v / --seed etc)
        group, group_count = ['--group', '--groups'].map do |arg|
          value = delete_argv(arg, argv) || raise("Did not find option #{arg}")
          value.to_i
        end
        dir = argv.shift
        raise "Unable to find directory #{dir.inspect}" unless File.exist?(dir.to_s)
        tests = [dir]
      else
        group = 1
        group_count = 1
        size = argv.index("--") || argv.size
        tests = argv.slice!(0, size)
        argv.shift # remove --
      end

      [group, group_count, tests]
    end

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

    def find_tests_for_group(group, group_count, tests, runtime_log)
      require 'parallel_tests/test/runner'

      group_by = (runtime_log ? :runtime : :filesize)
      tests = ParallelTests::Test::Runner.send(
        :tests_with_size,
        tests,
        runtime_log: runtime_log,
        group_by: group_by
      )
      groups = ParallelTests::Grouper.in_even_groups_by_size(tests, group_count, {})
      group = groups[group - 1] || raise("Group #{group} not found")

      # return tests with runtime
      tests = Hash[tests]
      group.map { |test| [test, (tests[test] if group_by == :runtime)] }
    end

    def delete_argv(name, argv)
      return unless index = argv.index(name)
      argv.delete_at(index)
      argv.delete_at(index) || raise("Missing argument for #{name}")
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
