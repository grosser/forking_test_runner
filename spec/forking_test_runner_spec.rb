require "spec_helper"
require "tempfile"

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
    old = {}
    hash.each { |k,v| old[k], env[k] = env[k], v }
    yield
  ensure
    old.each { |k,v| env[k] = v }
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

  it "runs tests without pollution" do
    result = runner("test")
    result.should include "simple_test.rb"
    result.should include "pollution_test.rb"
    result.should_not include "0 tests " # minitest was not disabled
    result.should_not include "Time:" # no runtime log -> no time info
  end

  it "runs tests without pollution" do
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

  # this test needs internet access
  it "records runtime" do
    with_env "TRAVIS_REPO_SLUG" => "test-slug", "TRAVIS_BUILD_NUMBER" => "build#{rand(999999)}" do
      result = runner("test --record-runtime amend")
      url = result[/curl \S+/] || raise("no command found")
      result = sh "curl --silent #{url}"
      assert_correct_runtime(result)
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
    result.should include "1 tests, 1 assertions"
    result.should include "AR IS UNDEFINED"
  end

  describe "rspec" do
    it "can run" do
      runner("spec --rspec").should include "1 example, 0 failures"
    end

    it "runs with arguments" do
      runner("spec --rspec --seed 12345").should include "Randomized with seed 12345"
    end

    it "runs with and groups" do
      runner("spec --rspec --group 1 --groups 1 --seed 12345").should include "Randomized with seed 12345"
    end
  end
end
