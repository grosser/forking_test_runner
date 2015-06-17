Run every test in a fork to avoid pollution and get clean output per test.
Forks are fast because they preload the test_helper + all fixtures.

Install
=======

```Bash
gem install forking_test_runner
```

```
forking-test-runner test
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
```

Usage
=====

Run it with individual files

```
forking-test-runner test/models/user_test.rb test/models/order_test.rb
```

### Simple parallel execution on CI

```
forking-test-runner test --group 1 --groups 20
```

### Make test groups take the same time

Record test runtime (on your CI, see other modes below)

```
forking-test-runner test --group 1 --groups 20 --record-runtime amend
```

Then download the runtime + commit it to your repo + run with runtime

```
forking-test-runner test --group 1 --groups 20 --runtime-log test/files/runtime.log
```

### Only provide output from failed tests

```
forking-test-runner test --quiet
```

### RSpec

Just add `--rspec`

### Options

```
--runtime-log LOG
--helper test/helpers/test_helper.rb
--group GROUP # starts at 1
--groups GROUPS
--record-runtime
    simple # write to local disc at location from --runtime-log or runtime.log
    amend # write from multiple remote workers via http://github.com/grosser/amend, needs TRAVIS_REPO_SLUG + TRAVIS_BUILD_NUMBER
--rspec
--no-fixtures
```

### Log aggregation

To analyze all builds try this [streaming travis log analyzer](https://gist.github.com/grosser/df68f5461d45601f37f0)
it will show all failures, the failed files and failed jobs.

Author
======
[Michael Grosser](http://grosser.it)<br/>
michael@grosser.it<br/>
License: MIT<br/>
[![Build Status](https://travis-ci.org/grosser/forking_test_runner.png)](https://travis-ci.org/grosser/forking_test_runner)
