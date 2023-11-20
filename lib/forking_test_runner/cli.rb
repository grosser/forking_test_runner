module ForkingTestRunner
  # read and delete options we support and pass the rest through to the underlying test runner (-v / --seed etc)
  module CLI
    OPTIONS = [
      [:rspec, "--rspec", "RSpec mode"],
      [:helper, "--helper", "Helper file to load before tests start", String],
      [:quiet, "--quiet", "Quiet"],
      [:no_fixtures, "--no-fixtures", "Do not load fixtures"],
      [:no_ar, "--no-ar", "Disable ActiveRecord logic"],
      [:merge_coverage, "--merge-coverage", "Merge base code coverage into individual files coverage and summarize coverage report"],
      [:only_merge_configure, "--only-merge-configure", "Do not merge unconfigured coverage to avoid overhead (needs --merge-coverage)"],
      [
        :record_runtime,
        "--record-runtime=MODE",
        "\n      Record test runtime:\n" <<
          "        simple = write to disk at --runtime-log)\n" <<
          "        amend  = write from multiple remote workers via http://github.com/grosser/amend, needs TRAVIS_REPO_SLUG & TRAVIS_BUILD_NUMBER",
        String
      ],
      [:runtime_log, "--runtime-log=FILE", "File to store runtime log in or runtime.log", String],
      [:parallel, "--parallel=NUM", "Number of parallel groups to run at once", Integer],
      [:group, "--group=NUM[,NUM]", "What group this is (use with --groups / starts at 1)", String],
      [:groups, "--groups=NUM", "How many groups there are in total (use with --group)", Integer],
      [:version, "--version", "Show version"],
      [:help, "--help", "Show help"]
    ]

    class << self
      def parse_options(argv)
        options = OPTIONS.each_with_object({}) do |(setting, flag, _, type), all|
          all[setting] = delete_argv(flag.split('=', 2)[0], argv, type: type)
        end

        # show version
        if options.fetch(:version)
          puts VERSION
          exit 0
        end

        # show help
        if options[:help]
          puts help
          exit 0
        end

        # check if we can use merge_coverage
        if options.fetch(:merge_coverage)
          abort "merge_coverage does not work on ruby prior to 2.3" if RUBY_VERSION < "2.3.0"
        end

        if !!options.fetch(:group) ^ !!options.fetch(:groups)
          abort "use --group and --groups together"
        end

        # all remaining non-flag options until the next flag must be tests
        next_flag = argv.index { |arg| arg.start_with?("-") } || argv.size
        tests = argv.slice!(0, next_flag)
        abort "No tests or folders found in arguments" if tests.empty?
        tests.each { |t| abort "Unable to find #{t}" unless File.exist?(t) }

        [options, tests]
      end

      private

      # fake parser that will print nicely
      def help
        OptionParser.new("forking-test-runner folder [options]", 32, '') do |opts|
          OPTIONS.each do |_, flag, desc, type|
            opts.on(flag, desc, type)
          end
        end
      end

      # we remove the args we understand and leave the rest alone
      # so minitest / rspec can read their own options (--seed / -v ...)
      #  - keep our options clear / unambiguous to avoid overriding
      #  - read all serial non-flag arguments as tests and leave only unknown options behind
      #  - use .fetch everywhere to make sure nothing is misspelled
      # GOOD: test --ours --theirs
      # OK: --ours test --theirs
      # BAD: --theirs test --ours
      def delete_argv(name, argv, type: nil)
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
end
