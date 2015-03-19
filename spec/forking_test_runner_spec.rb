require "spec_helper"

describe ForkingTestRunner do
  def runner(command, options={})
    sh("#{Bundler.root}/bin/forking-test-runner #{command}", options)
  end

  def sh(command, options={})
    result = Bundler.with_clean_env { `#{command} #{"2>&1" unless options[:keep_output]}` }
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
    result.should_not include "0 tests" # minitest was not disabled
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
    result = runner("test -- -v")
    result.should include "SimpleTest#test_transaction_0 ="
  end

  # this test needs internet access
  it "records runtime" do
    with_env "RECORD_RUNTIME" => "1", "TRAVIS_REPO_SLUG" => "test-slug", "TRAVIS_BUILD_NUMBER" => "build#{rand(999999)}" do
      result = runner("test")
      url = result[/curl \S+/] || raise("no command found")
      result = sh "curl --silent #{url}"
      result.gsub!(/:[\d\.]+/, "")
      result.split("\n").sort.should == [
        "test/another_test.rb",
        "test/pollution_test.rb",
        "test/simple_test.rb"
      ]
    end
  end

  it "uses recorded runtime" do
    result = runner("test --group 1 --groups 2 --runtime-log runtime.log")
    result.should include "Running tests test/another_test.rb\n" # only runs the 1 big test
    result.should include "Time: expected 1.0, actual 0." # per test time info
    result.should include "diff to expected" # global summary
  end
end
