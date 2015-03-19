module ForkingTestRunner
  class << self
    # This forces Rails to load all fixtures, then prevents it from deleting and then
    # re-inserting all fixtures when a test is run.
    # Saves us a couple of seconds when the test includes a call to fixtures :all.
    def preload_fixtures
      return if @preloaded
      @preloaded = true

      # reuse our pre-loaded fixtures even if we have a different connection
      class << ActiveRecord::Fixtures
        def cache_for_connection(connection)
          ActiveRecord::Fixtures.class_variable_get(:@@all_cached_fixtures)[:unique]
        end
      end

      ActiveSupport::TestCase.fixtures :all

      ActiveRecord::Fixtures.create_fixtures(
        ActiveRecord::TestCase.fixture_path,
        ActiveRecord::TestCase.fixture_table_names,
        ActiveRecord::TestCase.fixture_class_names
      )
    end

    # don't let minitest setup another exit hook
    def disable_minitest_autorun
      require 'minitest/unit'
      MiniTest::Unit.class_variable_set("@@installed_at_exit", true)
    end

    def enabled_minitest_autorun
      MiniTest::Unit.class_variable_set(:@@installed_at_exit, false)
      MiniTest::Unit.autorun
    end

    def run_test(file)
      preload_fixtures
      ActiveRecord::Base.connection.disconnect!
      child = fork do
        ActiveRecord::Base.establish_connection 'test'
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
  end
end
