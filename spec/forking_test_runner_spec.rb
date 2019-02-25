require "spec_helper"
require "tempfile"
require "active_record/version"

describe ForkingTestRunner do
  let(:root) { File.expand_path("../../", __FILE__) }

  def runner(command, options={})
    sh("bundle exec #{root}/bin/forking-test-runner #{command}", options)
  end

  def sh(command, options={})
    gemfile = ENV["BUNDLE_GEMFILE"]
    result = Bundler.with_clean_env do
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
    # this test needs internet access
    it "records runtime for travis" do
      with_env TRAVIS_REPO_SLUG: "test-slug", TRAVIS_BUILD_NUMBER: "build#{rand(999999)}" do
        result = runner("test --record-runtime amend")
        url = result[/curl \S+/] || raise("no command found")
        result = sh "curl --silent #{url}"
        assert_correct_runtime(result)
      end
    end

    # this test needs internet access
    it "records runtime for buildkite" do
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
        result.should include "KeyError: key not found"
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

  it "can run without activerecord" do
    result = runner("test/no_ar_test.rb --helper test/no_ar_helper.rb")
    result.should =~ /1 tests, 1 assertions|1 runs, 1 assertions/
    result.should include "AR IS UNDEFINED"
  end

  if RUBY_VERSION >= "2.3.0"
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

    if RUBY_VERSION >= "2.5.0"
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
    end
  else
    it "explodes when trying to use coverage" do
      result = with_env "COVERAGE" => "1" do
        runner("test/coverage.rb --merge-coverage", fail: true)
      end
      result.should include "merge_coverage does not work on ruby prior to 2.3"
    end
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
end
