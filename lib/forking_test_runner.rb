require 'benchmark'
require 'optparse'

module ForkingTestRunner
  CLEAR = "------"

  module CoverageCapture
    def capture_coverage!
      @capture_coverage = peek_result.dup
    end

    # override to add pre-fork captured coverage when someone asks for the results
    def result
      original = super
      return original unless @capture_coverage

      merged = original.dup
      @capture_coverage.each do |file, coverage|
        orig = merged[file]
        merged[file] = if orig
          merge_coverage(orig, coverage)
        else
          coverage
        end
      end
      merged
    end

    private

    # [nil,1,0] + [nil,nil,2] -> [nil,1,2]
    def merge_coverage(a, b)
      b.each_with_index.map do |b_count, i|
        a_count = a[i]
        (!b_count && !a_count) ? nil : b_count.to_i + a_count.to_i
      end
    end
  end

  class << self
    def cli(argv)
      @options, tests = parse_options(argv)

      disable_test_autorun

      load_test_env(@options.fetch(:helper))

      # figure out what we need to run
      runtime_log = @options.fetch(:runtime_log)
      group, group_count = find_group_args
      tests = find_tests_for_group(group, group_count, tests, runtime_log)

      if @options.fetch(:quiet)
        puts "Running #{tests.size} test files"
      else
        puts "Running tests #{tests.map(&:first).join(" ")}"
      end

      if ar?
        preload_fixtures
        ActiveRecord::Base.connection.disconnect!
      end

      Coverage.capture_coverage! if @options.fetch(:merge_coverage)

      # run all the tests
      results = tests.map do |file, expected|
        puts "#{CLEAR} >>> #{file} "
        time, success, output = benchmark { run_test(file) }

        puts output if !success && @options.fetch(:quiet)

        if runtime_log && !@options.fetch(:quiet)
          puts "Time: expected #{expected.round(2)}, actual #{time.round(2)}"
        end

        if !success || !@options.fetch(:quiet)
          puts "#{CLEAR} <<< #{file} ---- #{success ? "OK" : "Failed"}"
        end

        [file, time, expected, output, success]
      end

      unless @options.fetch(:quiet)
        # pretty print the results
        puts "\nResults:"
        puts results.
          sort_by { |_,_,_,_,r| r ? 0 : 1 }. # failures should be last so they are easy to find
          map { |f,_,_,_,r| "#{f}: #{r ? "OK" : "Fail"}"}
        puts
      end

      success = results.map(&:last).all?

      puts colorize(success, summarize_results(results.map { |r| r[3] }))

      if runtime_log
        # show how long they ran vs expected
        diff = results.map { |_,time,expected| time - expected }.inject(:+).to_f
        puts "Time: #{diff.round(2)} diff to expected"
      end

      if mode = @options.fetch(:record_runtime)
        # store runtime log
        log = runtime_log || 'runtime.log'
        record_test_runtime(mode, results, log)
      end

      # exit with success or failure
      success ? 0 : 1
    end

    private

    def colorize(green, string)
      if $stdout.tty?
        "\e[#{green ? 32 : 31}m#{string}\e[0m"
      else
        string
      end
    end

    def summarize_results(results)
      runner = if @options.fetch(:rspec)
        require 'parallel_tests/rspec/runner'
        ParallelTests::RSpec::Runner
      else
        require 'parallel_tests/test/runner'
        ParallelTests::Test::Runner
      end

      runner.summarize_results(results.map { |r| runner.find_results(r) })
    end

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

    def find_group_args
      if @options.fetch(:group) && @options.fetch(:groups)
        # delete options we want while leaving others as they are (-v / --seed etc)
        group = @options.fetch(:group)
        group_count = @options.fetch(:groups)
      else
        group = 1
        group_count = 1
      end

      [group, group_count]
    end

    def load_test_env(helper=nil)
      require 'rspec' if @options.fetch(:rspec)
      helper = helper || (@options.fetch(:rspec) ? "spec/spec_helper" : "test/test_helper")
      require "./#{helper}"
    end

    # This forces Rails to load all fixtures, then prevents it from
    # "deleting and re-inserting all fixtures" when a new connection is used (forked).
    def preload_fixtures
      return if @options.fetch(:no_fixtures)

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
      output = change_program_name_to file do
        fork_with_captured_output(!@options.fetch(:quiet)) do
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
      if @options.fetch(:rspec)
        if value
          exit(RSpec::Core::Runner.run([file] + ARGV))
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
          require(file.start_with?('/') ? file : "./#{file}")
        end
      end
    end

    # Option parsing is a bit wonky ... we remove the args we understand and leave the rest alone namely --seed and -v
    # but also whatever else ... and keep our options clear / unambiguous to avoid overriding anything
    # then also remove all non-flag arguments as these are the tests and leave only unknown options behind
    # using .fetch everywhere to make sure nothing is misspelled
    # GOOD: test --known --unknown
    # OK: --know test --unknown
    # BAD: --unknown test --known
    def parse_options(argv)
      arguments = [
        [:rspec, "--rspec", "RSpec mode"],
        [:helper, "--helper", "Helper file to load before tests start", String],
        [:quiet, "--quiet", "Quiet"],
        [:no_fixtures, "--no-fixtures", "Do not load fixtures"],
        [:merge_coverage, "--merge-coverage", "Merge base code coverage into indvidual files coverage, great for SingleCov"],
        [:record_runtime, "--record-runtime=MODE", "Record test runtime either simple (write to disk) or amend (combine via amend as a service) mode", String],
        [:runtime_log, "--runtime-log=FILE", "File to store runtime log in", String],
        [:group, "--group=NUM", "What group this is (use with --groups)", Integer],
        [:groups, "--groups=NUM", "How many groups there are in total (use with --group)", Integer],
        [:version, "--version", "Show version"],
        [:help, "--help", "Show help"]
      ]

      options = arguments.each_with_object({}) do |(setting, flag, _, type), all|
        all[setting] = delete_argv(flag.split('=', 2)[0], argv, type: type)
      end

      # show version
      if options.fetch(:version)
        puts VERSION
        exit 0
      end

      # # show help
      if options[:help]
        parser = OptionParser.new do |opts|
          opts.banner { "forking-test-runner folder [options]" }
          arguments.each do |_, flag, desc, type|
            opts.on(flag, desc, type)
          end
        end
        puts parser
        exit 0
      end

      # check if we can use merge_coverage
      if options.fetch(:merge_coverage)
        abort "merge_coverage does not work on ruby prior to 2.3" if RUBY_VERSION < "2.3.0"
        require 'coverage'
        klass = (class << Coverage; self; end)
        klass.prepend CoverageCapture
      end

      # all remaining non-flag options until the next flag must be tests
      next_flag = argv.index { |arg| arg.start_with?("-") } || argv.size
      tests = argv.slice!(0, next_flag)
      abort "No tests or folders found in arguments" if tests.empty?
      tests.each { |t| abort "Unable to find #{t}" unless File.exist?(t) }

      [options, tests]
    end

    def delete_argv(name, argv, type:)
      return unless index = argv.index(name)
      argv.delete_at(index)
      if type
        found = argv.delete_at(index) || raise("Missing argument for #{name}")
        send(type.name, found) # case found
      else
        true
      end
    end
  end
end
