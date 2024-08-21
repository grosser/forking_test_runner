require "spec_helper"
require "tempfile"
require "active_record/version"
require "json"
require "fileutils"

describe ForkingTestRunner do
  let(:root) { File.expand_path("../../", __FILE__) }

  def runner(command, options={})
    sh("bundle exec #{root}/bin/forking-test-runner #{command}", options)
  end

  def sh(command, options={})
    gemfile = ENV["BUNDLE_GEMFILE"]
    result = Bundler.with_unbundled_env do
      ENV["BUNDLE_GEMFILE"] = gemfile
      `#{command} #{"2>&1" unless options[:keep_output]}`
    end
    raise "#{options[:fail] ? "SUCCESS" : "FAIL"} #{command}\n#{result}" if $?.success? == !!options[:fail]
    result
  end

  def with_env(hash)
    env = Bundler::ORIGINAL_ENV
    old = env.dup
    hash.each { |k,v| env[k.to_s] = v }
    yield
  ensure
    env.replace(old)
  end

  def assert_correct_runtime(result)
    result.gsub!(/:[\d\.]+/, "")
    result.split("\n").sort.should == [
      "test/another_test.rb",
      "test/no_ar_test.rb",
      "test/pollution_test.rb",
      "test/simple_test.rb"
    ]
  end

  def restoring(file)
    content = File.read(file)
    yield
  ensure
    File.write(file, content)
  end

  around do |test|
    Dir.chdir File.expand_path("../dummy", __FILE__), &test
  end

  it "has a VERSION" do
    ForkingTestRunner::VERSION.should =~ /^[\.\da-z]+$/
  end

  it "shows --version" do
    runner("--version").should match(/\A\d+\.\d+\.\d+\n\z/)
  end

  it "passes -v to ruby to make verbose testing work" do
    runner("test/another_test.rb -v").should include("AnotherTest#test_true")
  end

  it "shows --help" do
    runner("--help").should include("forking-test-runner")
  end

  it "explains that using using --group without --groups does not work" do
    runner("--group 1", fail: true).should include("use --group and --groups together")
    runner("--groups 1", fail: true).should include("use --group and --groups together")
  end

  it "fails without tests" do
    runner("--meh", fail: true).should == "No tests or folders found in arguments\n"
  end

  it "fails with missing tests" do
    runner("meh", fail: true).should == "Unable to find meh\n"
  end

  it "runs tests without pollution" do
    result = runner("test")
    result.should include "simple_test.rb"
    result.should include "pollution_test.rb"
    result.should include "9 assertions, 0 errors, 0 failures"
    result.should_not include "0 tests " # minitest was not disabled
    result.should_not include "Time:" # no runtime log -> no time info
  end

  it "runs absolute files" do
    result = runner(File.expand_path('../dummy/test/simple_test.rb', __FILE__))
    result.should include "simple_test.rb"
  end

  it "fails when a test fails" do
    with_env "FAIL_NOW" => "1" do
      result = runner("test", fail: true)
      result.should_not include "/dummy/" # no absolute path
      result.should include "[test/pollution_test.rb:9]" # uses relative path
      result.should include "simple_test.rb ---- OK"
      result.should include "pollution_test.rb ---- Fail"
    end
  end

  it "keeps unrelated args for the test runner" do
    result = runner("test -v")
    result.should include "SimpleTest#test_transaction_0 ="
  end

  it "switches program name so rerun scripts can use the file name" do
    result = runner("test/show_program_name.rb")
    result.should include "PROGRAM IS test/show_program_name.rb YEAH"
  end

  describe "amend" do
    # this test needs internet access and amend service running
    xit "records runtime for travis" do
      with_env TRAVIS_REPO_SLUG: "test-slug", TRAVIS_BUILD_NUMBER: "build#{rand(999999)}" do
        result = runner("test --record-runtime amend")
        url = result[/curl \S+/] || raise("no command found")
        result = sh "curl --silent #{url}"
        assert_correct_runtime(result)
      end
    end

    # this test needs internet access and amend service running
    xit "records runtime for buildkite" do
      with_env BUILDKITE_JOB_ID: "#{rand(999999)}", BUILDKITE_ORG_SLUG: "foo", BUILDKITE_PIPELINE_SLUG: "bar" do
        result = runner("test --record-runtime amend")
        url = result[/curl \S+/] || raise("no command found")
        result = sh "curl --silent #{url}"
        assert_correct_runtime(result)
      end
    end

    # this test needs internet access
    it "fails when unable to determine unique slug" do
      with_env TRAVIS_REPO_SLUG: nil, TRAVIS_BUILD_NUMBER: nil do
        result = runner("test --record-runtime amend", fail: true)
        result.should include "key not found"
      end
    end
  end

  it "records simple runtime to disc" do
    restoring "runtime.log" do
      runner("test --record-runtime simple")
      result = File.read("runtime.log")
      assert_correct_runtime(result)
    end
  end

  it "uses recorded runtime" do
    result = runner("test --group 1 --groups 2 --runtime-log runtime.log")
    result.should include "Running tests test/another_test.rb\n" # only runs the 1 big test
    result.should include "Time: expected 1.0, actual 0." # per test time info
    result.should include "diff to expected" # global summary
  end

  it "can run multiple groups" do
    result = runner("test --group 1,2 --groups 4")
    result.scan("<<<").size.should == 2
  end

  it "can run without activerecord" do
    result = runner("test/no_ar_test.rb --helper test/no_ar_helper.rb")
    result.should =~ /1 tests, 1 assertions|1 runs, 1 assertions/
    result.should include "AR IS UNDEFINED"
  end

  it "can keep coverage across forks" do
    result = with_env "COVERAGE" => "line" do
      runner("test/coverage.rb --merge-coverage")
    end
    if ActiveRecord::VERSION::STRING < "4.2.0"
      # older rails versions do some evil monkey patching that prevents us from recording coverage during fixture load
      result.should include "user: [1, 1, 0, nil, nil] preloaded: [1, 1, 1, nil, nil, 1, 1, nil, nil]"
    else
      result.should include "user: [1, 1, 1, nil, nil] preloaded: [1, 1, 1, nil, nil, 1, 1, nil, nil]"
    end
  end

  it "can keep branch coverage across forks" do
    result = with_env "COVERAGE" => "branches" do
      runner("test/coverage.rb --merge-coverage")
    end
    result.should include "user: {:lines=>[1, 1, 1, nil, nil], :branches=>{[:if, 0, 3, 4, 3, 36]=>{[:then, 1, 3, 4, 3, 8]=>0, [:else, 2, 3, 4, 3, 36]=>1}}} preloaded: {:lines=>[1, 1, 1, nil, nil, 1, 1, nil, nil], :branches=>{}}"
  end

  it "can merge branch coverage" do
    ForkingTestRunner::CoverageCapture.merge_coverage(
      {"foo.rb" => {lines: [1,2,3], branches: {foo: {bar: 0, baz: 1}}}},
      {"foo.rb" => {lines: [1,2,3], branches: {foo: {bar: 1, baz: 0}}}}
    ).should == {"foo.rb" => {lines: [2,4,6], branches: {foo: {bar: 1, baz: 1}}}}
  end

  describe "quiet mode" do
    it "does not print test output" do
      result = runner("test --quiet")
      result.should include ">>>"
      result.should_not include "Finished"
      result.should_not include "<<<"
    end

    it "prints failures" do
      with_env "FAIL_NOW" => "1" do
        result = runner("test --quiet", fail: true)
        result.should include ">>>"
        result.should include "Finished"
        result.should include "<<<"
      end
    end
  end

  describe "parallel" do
    it "is fast and does not overlap output" do
      Benchmark.realtime do
        result = runner("test/slow_1.rb test/slow_2.rb --parallel 2 --helper test/no_ar_helper.rb")
        result.gsub!(/slow_\d/, "slow_d") || raise
        result.gsub!(/--seed \d+/, "--seed d") || raise
        result.gsub!(/0.\d+/, "0.0") || raise
        result.should == <<~TEXT
          Running tests test/slow_d.rb test/slow_d.rb
          ------ >>> test/slow_d.rb
          Run options: --seed d
          
          # Running:
          
          
          
          Finished in 0.0s, 0.0 runs/s, 0.0 assertions/s.
          
          0 runs, 0 assertions, 0 failures, 0 errors, 0 skips
          ------ <<< test/slow_d.rb ---- OK
          ------ >>> test/slow_d.rb
          Run options: --seed d
          
          # Running:
          
          
          
          Finished in 0.0s, 0.0 runs/s, 0.0 assertions/s.
          
          0 runs, 0 assertions, 0 failures, 0 errors, 0 skips
          ------ <<< test/slow_d.rb ---- OK
          
          Results:
          test/slow_d.rb: OK
          test/slow_d.rb: OK
          
          0 assertions, 0 errors, 0 failures, 0 runs, 0 skips
        TEXT
      end.should < 2
    end

    it "prints warnings immediately" do
      result = runner("test/warn_1.rb test/warn_2.rb --parallel 2 --helper test/no_ar_helper.rb")
      result.gsub!(/warn_\d/, "warn_d") || raise
      result.should include <<~TEXT
        Running tests test/warn_d.rb test/warn_d.rb
        WARNING
        WARNING
        ------ >>> test/warn_d.rb
      TEXT
    end

    it "fails when processor count makes no sense for given group count" do
      result = runner("test/warn_1.rb test/warn_2.rb --groups 6 --group 1,2 --parallel 3 --helper test/no_ar_helper.rb", fail: true)
      result.should include "Use the same amount of processors as groups"
    end

    it "can work quietly" do
      result = runner("test/warn_1.rb test/warn_2.rb --parallel 2 --helper test/no_ar_helper.rb --quiet")
      result.gsub!(/warn_\d/, "warn_d") || raise
      result.should == <<~TEXT
        Running 2 test files
        WARNING
        WARNING
        ------ >>> test/warn_d.rb
        ------ >>> test/warn_d.rb
        0 assertions, 0 errors, 0 failures, 0 runs, 0 skips
      TEXT
    end

    it "prints failures when quiet" do
      result = runner("test/warn_1.rb test/fail.rb --parallel 2 --helper test/no_ar_helper.rb --quiet", fail: true)
      result.should =~ /test\/fail.rb.*\nF\n.*Failure.*test\/fail.rb/m
    end

    it "can run with less than parallel files" do
      result = runner("test/no_ar_test.rb --parallel 10 --helper test/no_ar_helper.rb --quiet")
      result.should == <<~TEXT
        Running 1 test files
        ------ >>> test/no_ar_test.rb
        1 assertion, 0 errors, 0 failures, 1 run, 0 skips
      TEXT
    end

    it "sets TEST_ENV_NUMBER during helper and run" do
      result = runner("test/test_env_1.rb test/test_env_2.rb --parallel 2 --helper test/no_ar_helper.rb")
      result.should include "TEST ENV 2 <-> 2"
      result.should include "TEST ENV  <-> "
    end

    it "can run with AR" do
      runner("test/ --parallel 2")
    end

    xit "crashes nicely when test helper fails" do # TODO: somehow randomly breaks in CI
      with_env FORCE_TEST_ENV_NUMBER: '' do
        result = runner("test/simple_test.rb --parallel 2", fail: true)
        result.should include "Re-raised error from test helper: SQLite3::BusyException: database is locked"
        result.should include "/sqlite3/" # correct backtrace
      end
    end
  end

  describe "before_fork_callbacks and after_fork_callbacks" do
    before do
      @tempfile = Tempfile.new
    end

    after do
      @tempfile.close
      @tempfile.unlink
    end

    it "runs them" do
      with_env("DUMMY_SPEC_CALLBACK_FILE" =>  @tempfile.path) do
        runner("test/simple_test.rb")
      end
      @tempfile.read.should == "before_fork_called\nafter_fork_called\n"
    end
  end

  describe "rspec" do
    it "can run passing tests" do
      runner("spec/passing --rspec").should include "1 example, 0 failures"
    end

    it "returns a successful status code on passing tests" do
      runner("spec/passing --rspec")
    end

    it "can run failing tests" do
      runner("spec/failing --rspec", { fail: true }).should include "1 example, 1 failure"
    end

    it "runs with arguments" do
      runner("spec/passing --rspec --seed 12345").should include "Randomized with seed 12345"
    end

    it "runs with and groups" do
      runner("spec/passing --rspec --group 1 --groups 1 --seed 12345").should include "Randomized with seed 12345"
    end

    context 'when emitting debug' do
      context 'without --quiet' do
        let(:output_with_debug) { runner("spec/emitting --rspec") }

        it { output_with_debug.should include('Warning: Code Under Test') }
      end

      context 'with --quiet' do
        let(:output_with_debug) { runner("spec/emitting --rspec --quiet") }

        it { output_with_debug.should include('Warning: Code Under Test') }
      end
    end
  end

  describe ".summarize_partial_reports" do
    before do
      ForkingTestRunner::SingleCov = "fake"
      ForkingTestRunner::SingleCov.should_receive(:coverage_report).and_return "coverage/out.json"
      ForkingTestRunner::SingleCov.should_receive(:coverage_report=)
      ForkingTestRunner.instance_variable_set(:@options, {})
      Dir.mkdir "coverage"
    end

    after do
      FileUtils.rm_rf("coverage")
      ForkingTestRunner.send(:remove_const, :SingleCov)
    end

    it "works" do
      File.write("#{ForkingTestRunner::CONVERAGE_REPORT_PREFIX}1.json", JSON.dump("Minitest": {coverage: {b: [0, 1, 0]}}))
      File.write("#{ForkingTestRunner::CONVERAGE_REPORT_PREFIX}2.json", JSON.dump("Minitest": {coverage: {b: [1, 0, 0]}}))
      ForkingTestRunner.send(:summarize_partial_reports)
      out = JSON.parse(File.read("coverage/out.json"), symbolize_names: true)
      out[:"Minitest"].delete :timestamp
      out.should == { "Minitest": {coverage: { b: [1, 1, 0] } } }
    end
  end
end
