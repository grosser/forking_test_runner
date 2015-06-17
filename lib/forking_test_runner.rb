require 'benchmark'

module ForkingTestRunner
  CLEAR = "------"

  class << self
    def cli(argv)
      @rspec = delete_argv("--rspec", argv, arg: false)
      @no_fixtures = delete_argv("--no-fixtures", argv, arg: false)

      @quiet = delete_argv("--quiet", argv, arg: false)

      disable_test_autorun

      load_test_env(delete_argv("--helper", argv))

      # figure out what we need to run
      record_runtime = delete_argv("--record-runtime", argv)
      runtime_log = delete_argv("--runtime-log", argv)
      group, group_count, tests = extract_group_args(argv)
      tests = find_tests_for_group(group, group_count, tests, runtime_log)

      if @quiet
        puts "Running #{tests.size} test files"
      else
        puts "Running tests #{tests.map(&:first).join(" ")}"
      end

      # run all the tests
      results = tests.map do |file, expected|
        puts "#{CLEAR} >>> #{file} "
        time, success, output = benchmark { run_test(file) }

        puts output if !success && @quiet

        unless @quiet
          puts "Time: expected #{expected.round(2)}, actual #{time.round(2)}" if runtime_log
          puts "#{CLEAR} <<< #{file} ---- #{success ? "OK" : "Failed"}"
        end
        [file, time, expected, success]
      end

      puts

      unless @quiet
        # pretty print the results
        puts "\nResults:"
        puts results.
          sort_by { |_,_,_,r| r ? 0 : 1 }. # failures should be last so they are easy to find
          map { |f,_,_,r| "#{f}: #{r ? "OK" : "Fail"}"}
      end

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
      return [time, result].flatten
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
        size = argv.index { |arg| arg.start_with? "-" } || argv.size
        tests = argv.slice!(0, size)
      end

      [group, group_count, tests]
    end

    def load_test_env(helper=nil)
      require 'rspec' if @rspec
      helper = helper || (@rspec ? "spec/spec_helper" : "test/test_helper")
      require "./#{helper}"
    end

    # This forces Rails to load all fixtures, then prevents it from
    # "deleting and re-inserting all fixtures" when a new connection is used (forked).
    def preload_fixtures
      return if @preloaded || @no_fixtures
      @preloaded = true

      fixtures = (ActiveSupport::VERSION::MAJOR == 3 ? ActiveRecord::Fixtures : ActiveRecord::FixtureSet)

      # reuse our pre-loaded fixtures even if we have a different connection
      fixtures_eigenclass = class << fixtures; self; end
      fixtures_eigenclass.send(:define_method, :cache_for_connection) do |_connection|
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
    def disable_test_autorun
      toggle_test_autorun false
    end

    def enable_test_autorun(file)
      toggle_test_autorun true, file
    end

    def fork_with_captured_output(tee_to_stdout)
      rpipe, wpipe = IO.pipe

      child = fork do
        rpipe.close
        $stdout.reopen(wpipe)

        yield
      end

      wpipe.close

      buffer = ""

      while ch = rpipe.read(1)
        buffer << ch
        $stdout.write(ch) if tee_to_stdout
      end

      Process.wait(child)
      buffer
    end

    def run_test(file)
      if ar?
        preload_fixtures
        ActiveRecord::Base.connection.disconnect!
      end

      output = change_program_name_to file do
        fork_with_captured_output(!@quiet) do
          SimpleCov.pid = Process.pid if defined?(SimpleCov) && SimpleCov.respond_to?(:pid=) # trick simplecov into reporting in this fork
          if ar?
            key = (ActiveRecord::VERSION::STRING >= "4.1.0" ? :test : "test")
            ActiveRecord::Base.establish_connection key
          end
          enable_test_autorun(file)
        end
      end

      [$?.success?, output]
    end

    def change_program_name_to(name)
      old, $0 = $0, name
      yield
    ensure
      $0 = old
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

    def delete_argv(name, argv, arg: true)
      return unless index = argv.index(name)
      argv.delete_at(index)
      if arg
        argv.delete_at(index) || raise("Missing argument for #{name}")
      else
        true
      end
    end

    def ar?
      defined?(ActiveRecord::Base)
    end

    def minitest_class
      @minitest_class ||= begin
        require 'bundler/setup'
        gem 'minitest'
        if Gem.loaded_specs["minitest"].version.segments.first == 4 # 4.x
          require 'minitest/unit'
          MiniTest::Unit
        else
          require 'minitest'
          Minitest
        end
      end
    end

    def toggle_test_autorun(value, file=nil)
      if @rspec
        if value
          RSpec::Core::Runner.run([file] + ARGV)
        else
          require 'bundler/setup'
          require 'rspec'
          RSpec::Core::Runner.disable_autorun! # disable autorun in case the user left it in spec_helper.rb
          $LOAD_PATH.unshift "./lib"
          $LOAD_PATH.unshift "./spec"
        end
      else
        minitest_class.class_variable_set("@@installed_at_exit", !value)

        if value
          minitest_class.autorun
          require "./#{file}"
        end
      end
    end
  end
end
