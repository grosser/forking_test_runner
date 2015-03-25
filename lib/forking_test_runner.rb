module ForkingTestRunner
  class << self
    # This forces Rails to load all fixtures, then prevents it from deleting and then
    # re-inserting all fixtures when a test is run.
    # Saves us a couple of seconds when the test includes a call to fixtures :all.
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

    def enabled_minitest_autorun
      toggle_minitest_autorun true
    end

    def run_test(file)
      preload_fixtures
      ActiveRecord::Base.connection.disconnect!
      child = fork do
        key = (ActiveRecord::VERSION::STRING >= "4.1.0" ? :test : "test")
        ActiveRecord::Base.establish_connection key
        enabled_minitest_autorun
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

    private

    def toggle_minitest_autorun(value)
      begin
        require 'minitest/test' # only exists on > 5
      rescue LoadError
        require 'minitest/unit'
      end
      klass = if defined?(Minitest::Test)
        Minitest
      else
        # require 'minitest/unit'
        MiniTest::Unit
      end
      klass.class_variable_set("@@installed_at_exit", !value)
      klass.autorun if value
    end
  end
end
