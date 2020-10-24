Run every test in a fork to avoid global pollution and get clean results printed per test.
Forks are fast because they preload the test_helper + all activerecord fixtures.


Install
=======

```Bash
gem install forking_test_runner
```


Usage
=====

### Run folders

```
forking-test-runner test/
Running tests test/another_test.rb test/pollution_test.rb test/simple_test.rb
------ >>> test/another_test.rb
Run options: --seed 19151

# Running tests:

.

Finished tests in 0.002904s, 344.3526 tests/s, 344.3526 assertions/s.

1 tests, 1 assertions, 0 failures, 0 errors, 0 skips
------ <<< test/another_test.rb ---- OK

...

Results:
test/another_test.rb: OK
test/pollution_test.rb: OK
test/simple_test.rb: OK

9 assertions, 0 errors, 0 failures, 0 skips, 8 tests
```

### Run single files

```
forking-test-runner test/models/user_test.rb test/models/order_test.rb
```

### Parallel

Execute in `4` parallel processes, with `TEST_ENV_NUMBER` set to `'' / '2' / '3' / '4'`,
see [parallel_tests](https://github.com/grosser/parallel_tests) for setup helpers and details.
Stdout is synchronized and test results (start/output/finish) are printed when a test completes.

```
forking-test-runner test/ --parallel 4
```

### Parallel execution on CI

20 Parallel workers that each test 1 chunk of tests

```
forking-test-runner test/ --group 1 --groups 20
```

### Executing multiple groups

```
forking-test-runner test/ --group 1,2,3,4 --groups 20
forking-test-runner test/ --group 1,2,3,4 --groups 20 --parallel 4
```

### Make test groups take the same time

Record test runtime (on your CI, see other modes below)

```
forking-test-runner test/ --group 1 --groups 20 --record-runtime amend
```

Then download the runtime info + commit it to your repo + run with runtime

```
forking-test-runner test/ --group 1 --groups 20 --runtime-log test/files/runtime.log
```

### Only show output of failed tests

```
forking-test-runner test/ --quiet
```

### RSpec

Run with `--rspec`

### Options

<!-- Updated by rake bump:patch -->
```
forking-test-runner folder [options]
    --rspec                      RSpec mode
    --helper                     Helper file to load before tests start
    --quiet                      Quiet
    --no-fixtures                Do not load fixtures
    --no-ar                      Disable ActiveRecord logic
    --merge-coverage             Merge base code coverage into individual files coverage and summarize coverage report
    --report-line-coverage       Convert coverage report to line coverage (for compatibility)
    --record-runtime=MODE        
      Record test runtime:
        simple = write to disk at --runtime-log)
        amend  = write from multiple remote workers via http://github.com/grosser/amend, needs TRAVIS_REPO_SLUG & TRAVIS_BUILD_NUMBER
    --runtime-log=FILE           File to store runtime log in or runtime.log
    --parallel=NUM               Number of parallel groups to run at once
    --group=NUM[,NUM]            What group this is (use with --groups / starts at 1)
    --groups=NUM                 How many groups there are in total (use with --group)
    --version                    Show version
    --help                       Show help
```
<!-- Updated by rake bump:patch -->

### Supported CI Providers

 * Travis CI (TRAVIS_REPO_SLUG, TRAVIS_BUILD_NUMBER)
 * Buildkite (BUILDKITE_ORGANIZATION_SLUG, BUILDKITE_PIPELINE_SLUG, BUILDKITE_JOB_ID)

### Log aggregation

To analyze all builds try this [streaming travis log analyzer](https://gist.github.com/grosser/df68f5461d45601f37f0)
it will show all failures, the failed files and failed jobs.


Development
===========

 - `bundle exec rake` run tests
 - `bundle exec wwtd:local` run tests on all supported gemfiles
 - `bundle exec wwtd` run tests on all supported rubies and gemfiles


Authors
=======

### [Contributors](https://github.com/grosser/forking_test_runner/contributors)
 - [Ben Osheroff](https://github.com/osheroff)
 - [Barry Gordon](https://github.com/brrygrdn)

[Michael Grosser](https://grosser.it)<br/>
michael@grosser.it<br/>
License: MIT<br/>
[![Build Status](https://travis-ci.org/grosser/forking_test_runner.svg)](https://travis-ci.org/grosser/forking_test_runner)
