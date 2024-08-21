# frozen_string_literal: true
require 'benchmark'
require 'optparse'
require 'forking_test_runner/version'
require 'forking_test_runner/coverage_capture'
require 'forking_test_runner/cli'
require 'parallel'
require 'tempfile'

module ForkingTestRunner
  CLEAR = "------"
  CONVERAGE_REPORT_PREFIX = "coverage/fork-"

  class << self
    attr_accessor :before_fork_callbacks, :after_fork_callbacks

    def cli(argv)
      @options, tests = CLI.parse_options(argv)

      # figure out what we need to run
      runtime_log = @options.fetch(:runtime_log)
      groups, group_count = find_group_args
      parallel = @options.fetch(:parallel)
      test_groups =
        if parallel && !@options.fetch(:group)
          Array.new(parallel) { |i| find_tests_for_group(i + 1, parallel, tests, runtime_log) }
        else
          raise ArgumentError, "Use the same amount of processors as groups" if parallel && parallel != groups.count
          groups.map { |group| find_tests_for_group(group, group_count, tests, runtime_log) }
        end

      # say what we are running
      all_tests = test_groups.flatten(1)
      if @options.fetch(:quiet)
        puts "Running #{all_tests.size} test files"
      else
        puts "Running tests #{all_tests.map(&:first).join(" ")}"
      end

      @before_fork_callbacks = []
      @after_fork_callbacks = []

      # run all the tests
      results = with_lock do |lock|
        Parallel.map_with_index(test_groups, in_processes: parallel || 0) do |tests_group, env_index|
          if parallel
            ENV["TEST_ENV_NUMBER"] = (env_index == 0 ? '' : (env_index + 1).to_s) # NOTE: does not support first_is_1 option
          end

          reraise_clean_ar_error { load_test_env }

          tests_group.map do |file, expected|
            print_started file unless parallel
            result = [file, expected, *benchmark { run_test(file) }]
            sync_stdout lock do
              print_started file if parallel
              print_finished(*result)
            end
            result
          end
        end.flatten(1)
      end

      unless @options.fetch(:quiet)
        # pretty print the results
        puts "\nResults:"
        puts(
          results
                    .sort_by { |_, _, _, r, _| r ? 0 : 1 } # failures should be last so they are easy to find
                    .map { |f, _, _, r, _| "#{f}: #{r ? "OK" : "Fail"}" }
        )
        puts
      end

      success = results.map { |r| r[3] }.all?

      puts colorize(success, summarize_results(results.map { |r| r[4] }))

      if runtime_log
        # show how long they ran vs expected
        diff = results.map { |_, expected, time| time - expected }.inject(:+).to_f
        puts "Time: #{diff.round(2)} diff to expected"
      end

      if mode = @options.fetch(:record_runtime)
        # store runtime log
        log = runtime_log || 'runtime.log'
        record_test_runtime(mode, results, log)
      end

      summarize_partial_reports if partial_reports_for_single_cov?

      # exit with success or failure
      success ? 0 : 1
    end

    private

    def with_lock(&block)
      return yield unless @options.fetch(:parallel)
      Tempfile.open "forking-test-runner-lock", &block
    end

    def sync_stdout(lock)
      return yield unless @options.fetch(:parallel)
      begin
        lock.flock(File::LOCK_EX)
        yield
      ensure
        lock.flock(File::LOCK_UN)
      end
    end

    def print_started(file)
      puts "#{CLEAR} >>> #{file}"
    end

    def print_finished(file, expected, time, success, stdout)
      # print stdout if it was not shown before, but needs to be shown
      puts stdout if (!success && @options.fetch(:quiet)) || (@options.fetch(:parallel) && !@options.fetch(:quiet))

      if @options.fetch(:runtime_log) && !@options.fetch(:quiet)
        puts "Time: expected #{expected.round(2)}, actual #{time.round(2)}"
      end

      if !success || !@options.fetch(:quiet)
        puts "#{CLEAR} <<< #{file} ---- #{success ? "OK" : "Failed"}"
      end
    end

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
      time = Benchmark.realtime { result = yield }
      [time, *result]
    end

    # log runtime via dumping or curling it into the runtime log location
    def record_test_runtime(mode, results, log)
      data = results.map { |test, _, time| "#{test}:#{time.round(2)}" }.join("\n") << "\n"

      case mode
      when 'simple'
        File.write(log, data)
      when 'amend'
        if id = ENV["BUILDKITE_JOB_ID"]
          slug = "#{ENV.fetch("BUILDKITE_ORG_SLUG")}-#{ENV.fetch("BUILDKITE_PIPELINE_SLUG")}"
        else
          slug = ENV.fetch("TRAVIS_REPO_SLUG").sub("/", "-")
          id = ENV.fetch("TRAVIS_BUILD_NUMBER")
        end

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
      group = @options.fetch(:group)
      groups = @options.fetch(:groups)
      if group && groups
        # delete options we want while leaving others as they are (-v / --seed etc)
        [group.split(",").map { |g| Integer(g) }, groups]
      else
        [[1], 1]
      end
    end

    def load_test_env
      CoverageCapture.activate! if @options.fetch(:merge_coverage)

      load_test_helper

      if active_record?
        preload_fixtures
        ActiveRecord::Base.connection.disconnect!
      end
      @before_fork_callbacks.each(&:call)

      CoverageCapture.capture! if @options.fetch(:merge_coverage)
    end

    def reraise_clean_ar_error
      return yield unless @options.fetch(:parallel)

      e = begin
        yield
        nil
      rescue StandardError
        $!
      end

      # needs to be done outside of the rescue block to avoid inheriting the cause
      raise RuntimeError, "Re-raised error from test helper: #{e.message}", e.backtrace if e
    end

    def load_test_helper
      disable_test_autorun
      require 'rspec/core' if @options.fetch(:rspec)
      helper = @options.fetch(:helper) || (@options.fetch(:rspec) ? "spec/spec_helper" : "test/test_helper")
      require "./#{helper}"
    end

    # This forces Rails to load all fixtures, then prevents it from
    # "deleting and re-inserting all fixtures" when a new connection is used (forked).
    def preload_fixtures
      return if @options.fetch(:no_fixtures)

      # reuse our pre-loaded fixtures even if we have a different connection
      fixtures = ActiveRecord::FixtureSet
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

    def fork_with_captured_stdout
      rpipe, wpipe = IO.pipe

      child = Process.fork do
        rpipe.close
        preserve_tty { $stdout.reopen(wpipe) }
        yield
      end

      wpipe.close

      buffer = +""

      while ch = rpipe.read(1)
        buffer << ch
        $stdout.write(ch) if !@options.fetch(:quiet) && !@options.fetch(:parallel) # tee
      end

      Process.wait(child)
      buffer
    end

    # not tested via CI
    def preserve_tty
      was_tty = $stdout.tty?
      yield
      if was_tty
        def $stdout.tty?;
          true;
        end
      end
    end

    def run_test(file)
      stdout = change_program_name_to file do
        fork_with_captured_stdout do
          if defined?(SimpleCov)
            SimpleCov.pid = Process.pid
            SimpleCov.command_name file
          end
          if partial_reports_for_single_cov?
            SingleCov.coverage_report = "#{CONVERAGE_REPORT_PREFIX}#{Process.pid}.json"
          end

          @after_fork_callbacks.each(&:call)

          if active_record?
            key = (ActiveRecord::VERSION::STRING >= "4.1.0" ? :test : "test")
            ActiveRecord::Base.establish_connection key
          end
          enable_test_autorun(file)
        end
      end

      [$?.success?, stdout]
    end

    def partial_reports_for_single_cov?
      @options.fetch(:merge_coverage) && defined?(SingleCov) && SingleCov.respond_to?(:coverage_report=) && SingleCov.coverage_report
    end

    def change_program_name_to(name)
      return yield if @options.fetch(:parallel)
      begin
        old = $0
        $0 = name
        yield
      ensure
        $0 = old
      end
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
      tests = tests.to_h
      group.map { |test| [test, (tests[test] if group_by == :runtime)] }
    end

    def active_record?
      !@options.fetch(:no_ar) && defined?(ActiveRecord::Base)
    end

    def minitest_class
      @minitest_class ||= begin
        require 'bundler/setup'
        require 'minitest'
        Minitest
      end
    end

    def toggle_test_autorun(value, file = nil)
      if @options.fetch(:rspec)
        if value
          exit(RSpec::Core::Runner.run([file] + ARGV))
        else
          require 'bundler/setup'
          require 'rspec/core'
          RSpec::Core::Runner.disable_autorun! # disable autorun in case the user left it in spec_helper.rb
          $LOAD_PATH.unshift "./lib"
          $LOAD_PATH.unshift "./spec"
        end
      else
        minitest_class.class_variable_set("@@installed_at_exit", !value)

        if value
          minitest_class.autorun
          load file
        end
      end
    end

    def summarize_partial_reports
      reports = Dir.glob("#{CONVERAGE_REPORT_PREFIX}*")
      return if reports.empty?
      key = nil

      require "json" # not a global dependency
      coverage = reports.each_with_object({}) do |report, all|
        data = JSON.parse(File.read(report), symbolize_names: true)
        key ||= data.keys.first
        suites = data.values
        raise "Unsupported number of suites #{suites.size}" if suites.size != 1
        all.replace CoverageCapture.merge_coverage(all, suites.first.fetch(:coverage))
      ensure
        File.unlink(report) # do not leave junk behind
      end

      data = JSON.pretty_generate(key => { "coverage" => coverage, "timestamp" => Time.now.to_i })
      File.write(SingleCov.coverage_report, data)

      # make it not override our report when it finishes for main process
      SingleCov.coverage_report = nil
    end
  end
end
