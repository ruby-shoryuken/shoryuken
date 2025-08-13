## [7.0.0] - Unreleased
- Enhancement: Replace Concurrent::AtomicFixnum with pure Ruby AtomicCounter
  - Removes external dependency on concurrent-ruby for atomic fixnum operations
  - Introduces Shoryuken::Helpers::AtomicCounter as a thread-safe alternative using Mutex
  - Reduces gem footprint while maintaining full functionality

- Enhancement: Replace Concurrent::Hash with pure Ruby AtomicHash
  - Removes external dependency on concurrent-ruby for hash operations
  - Introduces Shoryuken::Helpers::AtomicHash with mutex-protected writes and concurrent reads
  - Ensures JRuby compatibility while maintaining high performance for read-heavy workloads
  - [#866](https://github.com/ruby-shoryuken/shoryuken/pull/866)
  - [#867](https://github.com/ruby-shoryuken/shoryuken/pull/867)
  - [#868](https://github.com/ruby-shoryuken/shoryuken/pull/868)

- Enhancement: Increase `SendMessageBatch` to 1MB to align with AWS
  - [#864](https://github.com/ruby-shoryuken/shoryuken/pull/864)

- Enhancement: Replace OpenStruct usage with Struct for inline execution
  - [#860](https://github.com/ruby-shoryuken/shoryuken/pull/860)

- Enhancement: Configure server side logging (BenMorganMY)
  - [#844](https://github.com/ruby-shoryuken/shoryuken/pull/844)

- Enhancement: Use -1 as thread priority
  - [#825](https://github.com/ruby-shoryuken/shoryuken/pull/825)

- Enhancement: Add Support for message_attributes to InlineExecutor
  - [#835](https://github.com/ruby-shoryuken/shoryuken/pull/835)

- Enhancement: Introduce trusted publishing
  - [#840](https://github.com/ruby-shoryuken/shoryuken/pull/840)

- Enhancement: Add enqueue_after_transaction_commit? for Rails 7.2 compatibility
  - [#777](https://github.com/ruby-shoryuken/shoryuken/pull/777)

- Enhancement: Bring Ruby 3.4 into the CI
  - [#805](https://github.com/ruby-shoryuken/shoryuken/pull/805)

- Fix integration tests by updating aws-sdk-sqs and replacing moto with LocalStack
  - [#782](https://github.com/ruby-shoryuken/shoryuken/pull/782)
  - [#783](https://github.com/ruby-shoryuken/shoryuken/pull/783)

- Breaking: Remove support of Ruby versions older than 3.1
  - [#783](https://github.com/ruby-shoryuken/shoryuken/pull/783)
  - [#850](https://github.com/ruby-shoryuken/shoryuken/pull/850)

- Breaking: Remove support of Rails versions older than 7.0
  - [#783](https://github.com/ruby-shoryuken/shoryuken/pull/783)
  - [#850](https://github.com/ruby-shoryuken/shoryuken/pull/850)

- Breaking: Require `aws-sdk-sqs` `>=` `1.66`:
  - [#783](https://github.com/ruby-shoryuken/shoryuken/pull/783)

## [v6.2.1] - 2024-02-09

- Bugfix: Not able to use extended polling strategy (#759)
  - [#759](https://github.com/ruby-shoryuken/shoryuken/pull/759)

## [v6.2.0] - 2024-02-04

- Enable hot-reload via adding ActiveSupport::Reloader delegate (#756)
  - [#756](https://github.com/ruby-shoryuken/shoryuken/pull/756)

## [v6.1.2] - 2024-01-30

- Fix activerecord 7.1 deprecation warnings
  - [#755](https://github.com/ruby-shoryuken/shoryuken/pull/755)

## [v6.1.1] - 2023-11-27

- Fix SQS API Changes causing nil returns instead of empty arrays
  - [#754](https://github.com/ruby-shoryuken/shoryuken/pull/754)
  - [#753](https://github.com/ruby-shoryuken/shoryuken/pull/753)

## [v6.1.0] - 2023-11-01

- Add GitHub Codespaces

  - [#698](https://github.com/ruby-shoryuken/shoryuken/pull/698)

- Fix spec for ruby 3.0

  - [#727](https://github.com/ruby-shoryuken/shoryuken/pull/727)

- Upgrade test matrix. Add Ruby 3.1, Ruby 3.2 and Rails 7

  - [#739](https://github.com/ruby-shoryuken/shoryuken/pull/739)

- Fire stopped event after executor is stopped

  - [#741](https://github.com/ruby-shoryuken/shoryuken/pull/741)

- Allow setup custom exception handlers for failing jobs

  - [#742](https://github.com/ruby-shoryuken/shoryuken/pull/742)

- Configure dependabot to update GH Actions

  - [#745](https://github.com/ruby-shoryuken/shoryuken/pull/745)

- Stop the dispatching of new messages when a SIGTERM signal has been received
  - [#750](https://github.com/ruby-shoryuken/shoryuken/pull/750)

## [v6.0.0] - 2022-02-18

- Breaking changes: Initialize Rails before parsing config file
  - [#686](https://github.com/ruby-shoryuken/shoryuken/pull/686)
  - Previously, Shoryuken read its configuration from an optional YAML file, then allowed CLI arguments to override those, then initialized the Rails application (provided that `--rails` or `-R` was specified). This behavior meant that the config file did not have access to things like environment variables that were initialized by Rails (such as when using `dotenv`). With this change, Rails is initialized much earlier in the process. After Rails is initialized, the YAML configuration file is interpreted, and CLI arguments are finally interpreted last. Most applications will not need to undergo changes in order to upgrade, but the new load order could technically result in different behavior depending on the application's YAML configuration file or Rails initializers.

## [v5.3.2] - 2022-01-19

- (Bugfix) Preserve queue weights when unpausing queues

  - [#687](https://github.com/ruby-shoryuken/shoryuken/pull/687)

- Improve error message on startup when shoryuken has insufficient permissions to access a queue
  - [#691](https://github.com/ruby-shoryuken/shoryuken/pull/691)

## [v5.3.1] - 2022-01-07

- (Bugfix) Fix issue where, when using the TSTP or USR1 signals for soft shutdowns, it was possible for shoryuken to terminate without first attempting to handle all messages it fetched from SQS
  - [#676](https://github.com/ruby-shoryuken/shoryuken/pull/676)

## [v5.3.0] - 2021-10-31

- (Refactor) Use Forwardable within Message to avoid method boilerplate

  - [#681](https://github.com/ruby-shoryuken/shoryuken/pull/681)

- Add basic health check API
  - [#679](https://github.com/ruby-shoryuken/shoryuken/pull/679)

## [v5.2.3] - 2021-07-29

- Fire new `:utilization_update` event any time a worker pool's utilization changes
  - [#673](https://github.com/ruby-shoryuken/shoryuken/pull/673)

## [v5.2.2] - 2021-06-22

- When using ActiveJob queue name prefixing, avoid applying prefix to queues configured with a URL or ARN
  - [#667](https://github.com/ruby-shoryuken/shoryuken/pull/667)

## [v5.2.1] - 2021-04-06

- Reduce message batch sizes in `shoryuken sqs requeue` and `shoryuken sqs mv` commands

  - [#666](https://github.com/ruby-shoryuken/shoryuken/pull/666)

- Fix bug in `shoryuken sqs requeue` and `shoryuken sqs mv` where those commands would exceed the SQS `SendMessageBatch` maximum payload size

  - [#663](https://github.com/ruby-shoryuken/shoryuken/issues/663)
  - [#664](https://github.com/ruby-shoryuken/shoryuken/pull/664)

- Remove test stub for `Concurrent.global_io_executor`

  - [#662](https://github.com/ruby-shoryuken/shoryuken/pull/662)

- Run integration tests on CI
  - [#660](https://github.com/ruby-shoryuken/shoryuken/pull/660)

## [v5.2.0] - 2021-02-26

- Set `executions` correctly for ActiveJob jobs
  - [#657](https://github.com/ruby-shoryuken/shoryuken/pull/657)

## [v5.1.1] - 2021-02-10

- Fix regression in Ruby 3.0 introduced in Shoryuken 5.1.0, where enqueueing jobs with ActiveJob to workers that used keyword arguments would fail
  - [#654](https://github.com/ruby-shoryuken/shoryuken/pull/654)

## [v5.1.0] - 2021-02-06

- Add support for specifying SQS SendMessage parameters with ActiveJob `.set`

  - [#635](https://github.com/ruby-shoryuken/shoryuken/pull/635)
  - [#648](https://github.com/ruby-shoryuken/shoryuken/pull/648)
  - [#651](https://github.com/ruby-shoryuken/shoryuken/pull/651)

- Unpause FIFO queues on worker completion

  - [#644](https://github.com/ruby-shoryuken/shoryuken/pull/644)

- Add multiple versions of Rails to test matrix

  - [#647](https://github.com/ruby-shoryuken/shoryuken/pull/647)

- Migrate from Travis CI to Github Actions
  - [#649](https://github.com/ruby-shoryuken/shoryuken/pull/649)
  - [#650](https://github.com/ruby-shoryuken/shoryuken/pull/650)
  - [#652](https://github.com/ruby-shoryuken/shoryuken/pull/652)

## [v5.0.6] - 2020-12-30

- Load ShoryukenConcurrentSendAdapter when loading Rails
  - [#642](https://github.com/ruby-shoryuken/shoryuken/pull/642)

## [v5.0.5] - 2020-06-07

- Add ability to configure queue by ARN
  - [#603](https://github.com/ruby-shoryuken/shoryuken/pull/603)

## [v5.0.4] - 2020-02-20

- Add endpoint option to SQS CLI
  - [#595](https://github.com/ruby-shoryuken/shoryuken/pull/595)

## [v5.0.3] - 2019-11-30

- Add support for sending messages asynchronous with Active Job using `shoryuken_concurrent_send`
  - [#589](https://github.com/ruby-shoryuken/shoryuken/pull/589)
  - [#588](https://github.com/ruby-shoryuken/shoryuken/pull/588)

## [v5.0.2] - 2019-11-02

- Fix Queue order is reversed if passed through CLI
  - [#571](https://github.com/ruby-shoryuken/shoryuken/pull/583)

## [v5.0.1] - 2019-06-19

- Add back attr_accessor for `stop_callback`
  - [#571](https://github.com/ruby-shoryuken/shoryuken/pull/571)

## [v5.0.0] - 2019-06-18

- Fix bug where empty queues were not paused in batch processing mode

  - [#569](https://github.com/ruby-shoryuken/shoryuken/pull/569)

- Preserve batch limit when receiving messages from a FIFO queue

  - [#563](https://github.com/ruby-shoryuken/shoryuken/pull/563)

- Replace static options with instance options
  - [#534](https://github.com/ruby-shoryuken/shoryuken/pull/534)

## [v4.0.3] - 2019-01-06

- Support delay per processing group
  - [#543](https://github.com/ruby-shoryuken/shoryuken/pull/543)

## [v4.0.2] - 2018-11-26

- Fix the delegated methods to public warning

  - [#536](https://github.com/ruby-shoryuken/shoryuken/pull/536)

- Specify exception class to `raise_error` matcher warning

  - [#537](https://github.com/ruby-shoryuken/shoryuken/pull/537)

- Fix spelling of "visibility"
  - [#538](https://github.com/ruby-shoryuken/shoryuken/pull/538)

## [v4.0.1] - 2018-11-21

- Allow caching visibility_timeout lookups

  - [#533](https://github.com/ruby-shoryuken/shoryuken/pull/533)

- Add queue name to inline executor
  - [#532](https://github.com/ruby-shoryuken/shoryuken/pull/532)

## [v4.0.0] - 2018-11-01

- Process messages to the same message group ID one by one
  - [#530](https://github.com/ruby-shoryuken/shoryuken/pull/530)

## [v3.3.1] - 2018-10-30

- Memoization of boolean causes extra calls to SQS
  - [#529](https://github.com/ruby-shoryuken/shoryuken/pull/529)

## [v3.3.0] - 2018-09-30

- Add support for TSTP

  - [#492](https://github.com/ruby-shoryuken/shoryuken/pull/492)

- Support an empty list of queues as a CLI argument

  - [#507](https://github.com/ruby-shoryuken/shoryuken/pull/507)

- Add batch support for inline workers

  - [#514](https://github.com/ruby-shoryuken/shoryuken/pull/514)

- Make InlineExecutor to behave as the DefaultExecutor when calling perform_in
  - [#518](https://github.com/ruby-shoryuken/shoryuken/pull/518)

## [v3.2.3] - 2018-03-25

- Don't force eager load for Rails 5

  - [#480](https://github.com/ruby-shoryuken/shoryuken/pull/480)

- Allow Batch Size to be Specified for Requeue

  - [#478](https://github.com/ruby-shoryuken/shoryuken/pull/478)

- Support FIFO queues in `shoryuken sqs` commands
  - [#473](https://github.com/ruby-shoryuken/shoryuken/pull/473)

## [v3.2.2] - 2018-02-13

- Fix requeue' for FIFO queues
  - [#48fcb42](https://github.com/ruby-shoryuken/shoryuken/commit/48fcb4260c3b41a9e45fa29bb857e8fa37dcee82)

## [v3.2.1] - 2018-02-12

- Support FIFO queues in `shoryuken sqs` commands

  - [#473](https://github.com/ruby-shoryuken/shoryuken/pull/473)

- Allow customizing the default executor launcher

  - [#469](https://github.com/ruby-shoryuken/shoryuken/pull/469)

- Exclude job_id from message deduplication when ActiveJob
  - [#462](https://github.com/ruby-shoryuken/shoryuken/pull/462)

## [v3.2.0] - 2018-01-03

- Preserve parent worker class options

  - [#451](https://github.com/ruby-shoryuken/shoryuken/pull/451)

- Add -t (shutdown timeout) option to CL

  - [#449](https://github.com/ruby-shoryuken/shoryuken/pull/449)

- Support inline (Active Job like) for standard workers
  - [#448](https://github.com/ruby-shoryuken/shoryuken/pull/448)

## [v3.1.12] - 2017-09-25

- Reduce fetch log verbosity
  - [#436](https://github.com/ruby-shoryuken/shoryuken/pull/436)

## [v3.1.11] - 2017-09-02

- Auto retry (up to 3 times) fetch errors
  - [#429](https://github.com/ruby-shoryuken/shoryuken/pull/429)

## [v3.1.10] - 2017-09-02

- Make Shoryuken compatible with AWS SDK 3 and 2
  - [#433](https://github.com/ruby-shoryuken/shoryuken/pull/433)

## [v3.1.9] - 2017-08-24

- Add support for adding a middleware to the front of chain

  - [#427](https://github.com/ruby-shoryuken/shoryuken/pull/427)

- Add support for dispatch fire event
  - [#426](https://github.com/ruby-shoryuken/shoryuken/pull/426)

## [v3.1.8] - 2017-08-17

- Make Polling strategy backward compatibility
  - [#424](https://github.com/ruby-shoryuken/shoryuken/pull/424)

## [v3.1.7] - 2017-07-31

- Allow polling strategy per group

  - [#417](https://github.com/ruby-shoryuken/shoryuken/pull/417)

- Add support for creating FIFO queues

  - [#419](https://github.com/ruby-shoryuken/shoryuken/pull/419)

- Allow receive message options per queue
  - [#420](https://github.com/ruby-shoryuken/shoryuken/pull/420)

## [v3.1.6] - 2017-07-24

- Fix issue with dispatch_loop and delays
  - [#416](https://github.com/ruby-shoryuken/shoryuken/pull/416)

## [v3.1.5] - 2017-07-23

- Fix memory leak

  - [#414](https://github.com/ruby-shoryuken/shoryuken/pull/414)

- Fail fast on bad queue URLs
  - [#413](https://github.com/ruby-shoryuken/shoryuken/pull/413)

## [v3.1.4] - 2017-07-14

- Require forwardable allowding to call `shoryuken` without `bundle exec`
  - [#409](https://github.com/ruby-shoryuken/shoryuken/pull/409)

## [v3.1.3] - 2017-07-11

- Add queue prefixing support for groups

  - [#405](https://github.com/ruby-shoryuken/shoryuken/pull/405)

- Remove dead code
  - [#402](https://github.com/ruby-shoryuken/shoryuken/pull/402)

## [v3.1.2] - 2017-07-06

- Fix stack level too deep on Ubuntu
  - [#400](https://github.com/ruby-shoryuken/shoryuken/pull/400)

## [v3.1.1] - 2017-07-05

- Reduce log verbosity introduced in 3.1.0

  - [#397](https://github.com/ruby-shoryuken/shoryuken/pull/397)

- Try to prevent stack level too deep on Ubuntu
  - [#396](https://github.com/ruby-shoryuken/shoryuken/pull/396)

## [v3.1.0] - 2017-07-02

- Add shoryuken sqs delete command

  - [#395](https://github.com/ruby-shoryuken/shoryuken/pull/395)

- Add processing groups support; Concurrency per queue support

  - [#389](https://github.com/ruby-shoryuken/shoryuken/pull/389)

- Terminate Shoryuken if the fetcher crashes
  - [#389](https://github.com/ruby-shoryuken/shoryuken/pull/389)

## [v3.0.11] - 2017-06-24

- Add shoryuken sqs create command
  - [#388](https://github.com/ruby-shoryuken/shoryuken/pull/388)

## [v3.0.10] - 2017-06-24

- Allow aws sdk v3

  - [#381](https://github.com/ruby-shoryuken/shoryuken/pull/381)

- Allow configuring Rails via the config file
  - [#387](https://github.com/ruby-shoryuken/shoryuken/pull/387)

## [v3.0.9] - 2017-06-05

- Allow configuring queue URLs instead of names
  - [#378](https://github.com/ruby-shoryuken/shoryuken/pull/378)

## [v3.0.8] - 2017-06-02

- Fix miss handling empty batch fetches

  - [#376](https://github.com/ruby-shoryuken/shoryuken/pull/376)

- Various minor styling changes :lipstick:

  - [#373](https://github.com/ruby-shoryuken/shoryuken/pull/373)

- Logout when batch delete returns any failure
  - [#371](https://github.com/ruby-shoryuken/shoryuken/pull/371)

## [v3.0.7] - 2017-05-18

- Trigger events for dispatch

  - [#362](https://github.com/ruby-shoryuken/shoryuken/pull/362)

- Log (warn) exponential backoff tries

  - [#365](https://github.com/ruby-shoryuken/shoryuken/pull/365)

- Fix displaying of long queue names in `shoryuken sqs ls`
  - [#366](https://github.com/ruby-shoryuken/shoryuken/pull/366)

## [v3.0.6] - 2017-04-11

- Fix delay option type
  - [#356](https://github.com/ruby-shoryuken/shoryuken/pull/356)

## [v3.0.5] - 2017-04-09

- Pause endless dispatcher to avoid CPU overload

  - [#354](https://github.com/ruby-shoryuken/shoryuken/pull/354)

- Auto log processor errors

  - [#355](https://github.com/ruby-shoryuken/shoryuken/pull/355)

- Add a delay as a CLI param

  - [#350](https://github.com/ruby-shoryuken/shoryuken/pull/350)

- Add `sqs purge` command. See https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_PurgeQueue.html
  - [#344](https://github.com/ruby-shoryuken/shoryuken/pull/344)

## [v3.0.4] - 2017-03-24

- Add `sqs purge` command. See https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_PurgeQueue.html

  - [#344](https://github.com/ruby-shoryuken/shoryuken/pull/344)

- Fix "Thread exhaustion" error. This issue was most noticed when using long polling. @waynerobinson :beers: for pairing up on this.
  - [#345](https://github.com/ruby-shoryuken/shoryuken/pull/345)

## [v3.0.3] - 2017-03-19

- Update `sqs` CLI commands to use `get_queue_url` when appropriated
  - [#341](https://github.com/ruby-shoryuken/shoryuken/pull/341)

## [v3.0.2] - 2017-03-19

- Fix custom SQS client initialization
  - [#335](https://github.com/ruby-shoryuken/shoryuken/pull/335)

## [v3.0.1] - 2017-03-13

- Fix commands sqs mv and dump `options.delete` checker
  - [#332](https://github.com/ruby-shoryuken/shoryuken/pull/332)

## [v3.0.0] - 2017-03-12

- Replace Celluloid with Concurrent Ruby

  - [#291](https://github.com/ruby-shoryuken/shoryuken/pull/291)

- Remove AWS configuration from Shoryuken. Now AWS should be configured from outside. Check [this](https://github.com/ruby-shoryuken/shoryuken/wiki/Configure-the-AWS-Client) for more details

  - [#317](https://github.com/ruby-shoryuken/shoryuken/pull/317)

- Remove deprecation warnings

  - [#326](https://github.com/ruby-shoryuken/shoryuken/pull/326)

- Allow dynamic adding queues

  - [#322](https://github.com/ruby-shoryuken/shoryuken/pull/322)

- Support retry_intervals passed in as a lambda. Auto coerce intervals into integer

  - [#329](https://github.com/ruby-shoryuken/shoryuken/pull/329)

- Add SQS commands `shoryuken help sqs`, such as `ls`, `mv`, `dump` and `requeue`
  - [#330](https://github.com/ruby-shoryuken/shoryuken/pull/330)

## [v2.1.3] - 2017-01-27

- Show a warn message when batch isn't supported

  - [#302](https://github.com/ruby-shoryuken/shoryuken/pull/302)

- Require Celluloid ~> 17

  - [#305](https://github.com/ruby-shoryuken/shoryuken/pull/305)

- Fix excessive logging when 0 messages found
  - [#307](https://github.com/ruby-shoryuken/shoryuken/pull/307)

## [v2.1.2] - 2016-12-22

- Fix loading `logfile` from shoryuken.yml

  - [#296](https://github.com/ruby-shoryuken/shoryuken/pull/296)

- Add support for Strict priority polling (pending documentation)

  - [#288](https://github.com/ruby-shoryuken/shoryuken/pull/288)

- Add `test_workers` for end-to-end testing supporting

  - [#286](https://github.com/ruby-shoryuken/shoryuken/pull/286)

- Update README documenting `configure_client` and `configure_server`

  - [#283](https://github.com/ruby-shoryuken/shoryuken/pull/283)

- Fix memory leak caused by async tracking busy threads

  - [#289](https://github.com/ruby-shoryuken/shoryuken/pull/289)

- Refactor fetcher, polling strategy and manager
  - [#284](https://github.com/ruby-shoryuken/shoryuken/pull/284)

## [v2.1.1] - 2016-12-05

- Fix aws deprecation warning message
  - [#279](https://github.com/ruby-shoryuken/shoryuken/pull/279)

## [v2.1.0] - 2016-12-03

- Fix celluloid "running in BACKPORTED mode" warning

  - [#260](https://github.com/ruby-shoryuken/shoryuken/pull/260)

- Allow setting the aws configuration in 'Shoryuken.configure_server'

  - [#252](https://github.com/ruby-shoryuken/shoryuken/pull/252)

- Allow requiring a file or dir a through `-r`

  - [#248](https://github.com/ruby-shoryuken/shoryuken/pull/248)

- Reduce info log verbosity

  - [#243](https://github.com/ruby-shoryuken/shoryuken/pull/243)

- Fix auto extender when using ActiveJob

  - [#3213](https://github.com/ruby-shoryuken/shoryuken/pull/213)

- Add FIFO queue support

  - [#272](https://github.com/ruby-shoryuken/shoryuken/issues/272)

- Deprecates initialize_aws

  - [#269](https://github.com/ruby-shoryuken/shoryuken/pull/269)

- [Other miscellaneous updates](https://github.com/ruby-shoryuken/shoryuken/compare/v2.0.11...v2.1.0)

## [v2.0.11] - 2016-07-02

- Same as 2.0.10. Unfortunately 2.0.10 was removed `yanked` by mistake from RubyGems.
  - [#b255bc3](https://github.com/ruby-shoryuken/shoryuken/commit/b255bc3)

## [v2.0.10] - 2016-06-09

- Fix manager #225
  - [#226](https://github.com/ruby-shoryuken/shoryuken/pull/226)

## [v2.0.9] - 2016-06-08

- Fix daemonization broken in #219
  - [#224](https://github.com/ruby-shoryuken/shoryuken/pull/224)

## [v2.0.8] - 2016-06-07

- Fix daemonization
  - [#223](https://github.com/ruby-shoryuken/shoryuken/pull/223)

## [v2.0.7] - 2016-06-06

- Daemonize before loading environment

  - [#219](https://github.com/ruby-shoryuken/shoryuken/pull/219)

- Fix initialization when using rails

  - [#197](https://github.com/ruby-shoryuken/shoryuken/pull/197)

- Improve message fetching

  - [#214](https://github.com/ruby-shoryuken/shoryuken/pull/214)
  - [#f4640d9](https://github.com/ruby-shoryuken/shoryuken/commit/f4640d9)

- Fix hard shutdown if there are some busy workers when signal received

  - [#215](https://github.com/ruby-shoryuken/shoryuken/pull/215)

- Fix `rake console` task

  - [#208](https://github.com/ruby-shoryuken/shoryuken/pull/208)

- Isolate `MessageVisibilityExtender` as new middleware

  - [#199](https://github.com/ruby-shoryuken/shoryuken/pull/190)

- Fail on non-existent queues
  - [#196](https://github.com/ruby-shoryuken/shoryuken/pull/196)

## [v2.0.6] - 2016-04-18

- Fix log initialization introduced by #191
  - [#195](https://github.com/ruby-shoryuken/shoryuken/pull/195)

## [v2.0.5] - 2016-04-17

- Fix log initialization when using `Shoryuken::EnvironmentLoader#load`

  - [#191](https://github.com/ruby-shoryuken/shoryuken/pull/191)

  - Fix `enqueue_at` in the ActiveJob Adapter
  - [#182](https://github.com/ruby-shoryuken/shoryuken/pull/182)

## [v2.0.4] - 2016-02-04

- Add Rails 3 support

  - [#175](https://github.com/ruby-shoryuken/shoryuken/pull/175)

- Allow symbol as a queue name in shoryuken_options

  - [#177](https://github.com/ruby-shoryuken/shoryuken/pull/177)

- Make sure bundler is always updated on Travis CI

  - [#176](https://github.com/ruby-shoryuken/shoryuken/pull/176)

- Add Rails 5 compatibility
  - [#174](https://github.com/ruby-shoryuken/shoryuken/pull/174)

## [v2.0.3] - 2015-12-30

- Allow multiple queues per worker

  - [#164](https://github.com/ruby-shoryuken/shoryuken/pull/164)

- Fix typo
  - [#166](https://github.com/ruby-shoryuken/shoryuken/pull/166)

## [v2.0.2] - 2015-10-27

- Fix warnings that are triggered in some cases with the raise_error matcher

  - [#144](https://github.com/ruby-shoryuken/shoryuken/pull/144)

- Add lifecycle event registration support

  - [#141](https://github.com/ruby-shoryuken/shoryuken/pull/141)

- Allow passing array of messages to send_messages

  - [#140](https://github.com/ruby-shoryuken/shoryuken/pull/140)

- Fix Active Job queue prefixing in Rails apps

  - [#139](https://github.com/ruby-shoryuken/shoryuken/pull/139)

- Enable override the default queue with a :queue option
  - [#147](https://github.com/ruby-shoryuken/shoryuken/pull/147)

## [v2.0.1] - 2015-10-09

- Bump aws-sdk to ~> 2
  - [#138](https://github.com/ruby-shoryuken/shoryuken/pull/138)

## [v2.0.0] - 2015-09-22

- Allow configuration of SQS/SNS endpoints via environment variables

  - [#130](https://github.com/ruby-shoryuken/shoryuken/pull/130)

- Expose queue_name in the message object

  - [#127](https://github.com/ruby-shoryuken/shoryuken/pull/127)

- README updates
  - [#122](https://github.com/ruby-shoryuken/shoryuken/pull/122)
  - [#120](https://github.com/ruby-shoryuken/shoryuken/pull/120)
