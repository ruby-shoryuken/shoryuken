## [v5.0.5] - 2020-06-07

- Add ability to configure queue by ARN
  - [#603](https://github.com/phstc/shoryuken/pull/603)

## [v5.0.4] - 2020-02-20

- Add endpoint option to SQS CLI
  - [#595](https://github.com/phstc/shoryuken/pull/595)

## [v5.0.3] - 2019-11-30

- Add support for sending messages asynchronous with Active Job using `shoryuken_concurrent_send`
  - [#589](https://github.com/phstc/shoryuken/pull/589)
  - [#588](https://github.com/phstc/shoryuken/pull/588)

## [v5.0.2] - 2019-11-02

- Fix Queue order is reversed if passed through CLI
  - [#571](https://github.com/phstc/shoryuken/pull/583)

## [v5.0.1] - 2019-06-19

- Add back attr_accessor for `stop_callback`
  - [#571](https://github.com/phstc/shoryuken/pull/571)

## [v5.0.0] - 2019-06-18

- Fix bug where empty queues were not paused in batch processing mode
  - [#569](https://github.com/phstc/shoryuken/pull/569)

- Preserve batch limit when receiving messages from a FIFO queue
  - [#563](https://github.com/phstc/shoryuken/pull/563)

- Replace static options with instance options
  - [#534](https://github.com/phstc/shoryuken/pull/534)

## [v4.0.3] - 2019-01-06

- Support delay per processing group
  - [#543](https://github.com/phstc/shoryuken/pull/543)

## [v4.0.2] - 2018-11-26

- Fix the delegated methods to public warning
  - [#536](https://github.com/phstc/shoryuken/pull/536)

- Specify exception class to `raise_error` matcher warning
  - [#537](https://github.com/phstc/shoryuken/pull/537)

- Fix spelling of "visibility"
  - [#538](https://github.com/phstc/shoryuken/pull/538)

## [v4.0.1] - 2018-11-21

- Allow caching visibility_timeout lookups
  - [#533](https://github.com/phstc/shoryuken/pull/533)

- Add queue name to inline executor
  - [#532](https://github.com/phstc/shoryuken/pull/532)

## [v4.0.0] - 2018-11-01

- Process messages to the same message group ID one by one
  - [#530](https://github.com/phstc/shoryuken/pull/530)

## [v3.3.1] - 2018-10-30

- Memoization of boolean causes extra calls to SQS
  - [#529](https://github.com/phstc/shoryuken/pull/529)

## [v3.3.0] - 2018-09-30

- Add support for TSTP
  - [#492](https://github.com/phstc/shoryuken/pull/492)

- Support an empty list of queues as a CLI argument
  - [#507](https://github.com/phstc/shoryuken/pull/507)

- Add batch support for inline workers
  - [#514](https://github.com/phstc/shoryuken/pull/514)

- Make InlineExecutor to behave as the DefaultExecutor when calling perform_in
  - [#518](https://github.com/phstc/shoryuken/pull/518)

## [v3.2.3] - 2018-03-25

- Don't force eager load for Rails 5
  - [#480](https://github.com/phstc/shoryuken/pull/480)

- Allow Batch Size to be Specified for Requeue
  - [#478](https://github.com/phstc/shoryuken/pull/478)

- Support FIFO queues in `shoryuken sqs` commands
  - [#473](https://github.com/phstc/shoryuken/pull/473)

## [v3.2.2] - 2018-02-13

- Fix requeue' for FIFO queues
  - [#48fcb42](https://github.com/phstc/shoryuken/commit/48fcb4260c3b41a9e45fa29bb857e8fa37dcee82)

## [v3.2.1] - 2018-02-12

- Support FIFO queues in `shoryuken sqs` commands
  - [#473](https://github.com/phstc/shoryuken/pull/473)

- Allow customizing the default executor launcher
  - [#469](https://github.com/phstc/shoryuken/pull/469)

- Exclude job_id from message deduplication when ActiveJob
  - [#462](https://github.com/phstc/shoryuken/pull/462)

## [v3.2.0] - 2018-01-03

- Preserve parent worker class options
  - [#451](https://github.com/phstc/shoryuken/pull/451)

- Add -t (shutdown timeout) option to CL
  - [#449](https://github.com/phstc/shoryuken/pull/449)

- Support inline (Active Job like) for standard workers
  - [#448](https://github.com/phstc/shoryuken/pull/448)

## [v3.1.12] - 2017-09-25

- Reduce fetch log verbosity
  - [#436](https://github.com/phstc/shoryuken/pull/436)

## [v3.1.11] - 2017-09-02

- Auto retry (up to 3 times) fetch errors
  - [#429](https://github.com/phstc/shoryuken/pull/429)

## [v3.1.10] - 2017-09-02

- Make Shoryuken compatible with AWS SDK 3 and 2
  - [#433](https://github.com/phstc/shoryuken/pull/433)

## [v3.1.9] - 2017-08-24

- Add support for adding a middleware to the front of chain
  - [#427](https://github.com/phstc/shoryuken/pull/427)

- Add support for dispatch fire event
  - [#426](https://github.com/phstc/shoryuken/pull/426)

## [v3.1.8] - 2017-08-17

- Make Polling strategy backward compatibility
  - [#424](https://github.com/phstc/shoryuken/pull/424)

## [v3.1.7] - 2017-07-31

- Allow polling strategy per group
  - [#417](https://github.com/phstc/shoryuken/pull/417)

- Add support for creating FIFO queues
  - [#419](https://github.com/phstc/shoryuken/pull/419)

- Allow receive message options per queue
  - [#420](https://github.com/phstc/shoryuken/pull/420)

## [v3.1.6] - 2017-07-24

- Fix issue with dispatch_loop and delays
  - [#416](https://github.com/phstc/shoryuken/pull/416)

## [v3.1.5] - 2017-07-23

- Fix memory leak
  - [#414](https://github.com/phstc/shoryuken/pull/414)

- Fail fast on bad queue URLs
  - [#413](https://github.com/phstc/shoryuken/pull/413)

## [v3.1.4] - 2017-07-14

- Require forwardable allowding to call `shoryuken` without `bundle exec`
  - [#409](https://github.com/phstc/shoryuken/pull/409)

## [v3.1.3] - 2017-07-11

- Add queue prefixing support for groups
  - [#405](https://github.com/phstc/shoryuken/pull/405)

- Remove dead code
  - [#402](https://github.com/phstc/shoryuken/pull/402)

## [v3.1.2] - 2017-07-06

- Fix stack level too deep on Ubuntu
  - [#400](https://github.com/phstc/shoryuken/pull/400)

## [v3.1.1] - 2017-07-05

- Reduce log verbosity introduced in 3.1.0
  - [#397](https://github.com/phstc/shoryuken/pull/397)

- Try to prevent stack level too deep on Ubuntu
  - [#396](https://github.com/phstc/shoryuken/pull/396)

## [v3.1.0] - 2017-07-02

- Add shoryuken sqs delete command
  - [#395](https://github.com/phstc/shoryuken/pull/395)

- Add processing groups support; Concurrency per queue support
  - [#389](https://github.com/phstc/shoryuken/pull/389)

- Terminate Shoryuken if the fetcher crashes
  - [#389](https://github.com/phstc/shoryuken/pull/389)

## [v3.0.11] - 2017-06-24

- Add shoryuken sqs create command
  - [#388](https://github.com/phstc/shoryuken/pull/388)

## [v3.0.10] - 2017-06-24

- Allow aws sdk v3
  - [#381](https://github.com/phstc/shoryuken/pull/381)

- Allow configuring Rails via the config file
  - [#387](https://github.com/phstc/shoryuken/pull/387)

## [v3.0.9] - 2017-06-05

- Allow configuring queue URLs instead of names
  - [#378](https://github.com/phstc/shoryuken/pull/378)

## [v3.0.8] - 2017-06-02

- Fix miss handling empty batch fetches
  - [#376](https://github.com/phstc/shoryuken/pull/376)

- Various minor styling changes :lipstick:
  - [#373](https://github.com/phstc/shoryuken/pull/373)

- Logout when batch delete returns any failure
  - [#371](https://github.com/phstc/shoryuken/pull/371)

## [v3.0.7] - 2017-05-18

- Trigger events for dispatch
  - [#362](https://github.com/phstc/shoryuken/pull/362)

- Log (warn) exponential backoff tries
  - [#365](https://github.com/phstc/shoryuken/pull/365)

- Fix displaying of long queue names in `shoryuken sqs ls`
  - [#366](https://github.com/phstc/shoryuken/pull/366)

## [v3.0.6] - 2017-04-11

- Fix delay option type
  - [#356](https://github.com/phstc/shoryuken/pull/356)

## [v3.0.5] - 2017-04-09

- Pause endless dispatcher to avoid CPU overload
  - [#354](https://github.com/phstc/shoryuken/pull/354)

- Auto log processor errors
  - [#355](https://github.com/phstc/shoryuken/pull/355)

- Add a delay as a CLI param
  - [#350](https://github.com/phstc/shoryuken/pull/350)

- Add `sqs purge` command. See https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_PurgeQueue.html
  - [#344](https://github.com/phstc/shoryuken/pull/344)

## [v3.0.4] - 2017-03-24

- Add `sqs purge` command. See https://docs.aws.amazon.com/AWSSimpleQueueService/latest/APIReference/API_PurgeQueue.html
  - [#344](https://github.com/phstc/shoryuken/pull/344)

- Fix "Thread exhaustion" error. This issue was most noticed when using long polling. @waynerobinson :beers: for pairing up on this.
  - [#345](https://github.com/phstc/shoryuken/pull/345)

## [v3.0.3] - 2017-03-19

- Update `sqs` CLI commands to use `get_queue_url` when appropriated
  - [#341](https://github.com/phstc/shoryuken/pull/341)

## [v3.0.2] - 2017-03-19

- Fix custom SQS client initialization
  - [#335](https://github.com/phstc/shoryuken/pull/335)

## [v3.0.1] - 2017-03-13

- Fix commands sqs mv and dump `options.delete` checker
  - [#332](https://github.com/phstc/shoryuken/pull/332)

## [v3.0.0] - 2017-03-12

- Replace Celluloid with Concurrent Ruby
  - [#291](https://github.com/phstc/shoryuken/pull/291)

- Remove AWS configuration from Shoryuken. Now AWS should be configured from outside. Check [this](https://github.com/phstc/shoryuken/wiki/Configure-the-AWS-Client) for more details
  - [#317](https://github.com/phstc/shoryuken/pull/317)

- Remove deprecation warnings
  - [#326](https://github.com/phstc/shoryuken/pull/326)

- Allow dynamic adding queues
  - [#322](https://github.com/phstc/shoryuken/pull/322)

- Support retry_intervals passed in as a lambda. Auto coerce intervals into integer
  - [#329](https://github.com/phstc/shoryuken/pull/329)

- Add SQS commands `shoryuken help sqs`, such as `ls`, `mv`, `dump` and `requeue`
  - [#330](https://github.com/phstc/shoryuken/pull/330)

## [v2.1.3] - 2017-01-27

- Show a warn message when batch isn't supported
  - [#302](https://github.com/phstc/shoryuken/pull/302)

- Require Celluloid ~> 17
  - [#305](https://github.com/phstc/shoryuken/pull/305)

- Fix excessive logging when 0 messages found
  - [#307](https://github.com/phstc/shoryuken/pull/307)

## [v2.1.2] - 2016-12-22

- Fix loading `logfile` from shoryuken.yml
  - [#296](https://github.com/phstc/shoryuken/pull/296)

- Add support for Strict priority polling (pending documentation)
  - [#288](https://github.com/phstc/shoryuken/pull/288)

- Add `test_workers` for end-to-end testing supporting
  - [#286](https://github.com/phstc/shoryuken/pull/286)

- Update README documenting `configure_client` and `configure_server`
  - [#283](https://github.com/phstc/shoryuken/pull/283)

- Fix memory leak caused by async tracking busy threads
  - [#289](https://github.com/phstc/shoryuken/pull/289)

- Refactor fetcher, polling strategy and manager
  - [#284](https://github.com/phstc/shoryuken/pull/284)

## [v2.1.1] - 2016-12-05

- Fix aws deprecation warning message
  - [#279](https://github.com/phstc/shoryuken/pull/279)

## [v2.1.0] - 2016-12-03

- Fix celluloid "running in BACKPORTED mode" warning
  - [#260](https://github.com/phstc/shoryuken/pull/260)

- Allow setting the aws configuration in 'Shoryuken.configure_server'
  - [#252](https://github.com/phstc/shoryuken/pull/252)

- Allow requiring a file or dir a through `-r`
  - [#248](https://github.com/phstc/shoryuken/pull/248)

- Reduce info log verbosity
  - [#243](https://github.com/phstc/shoryuken/pull/243)

- Fix auto extender when using ActiveJob
  - [#3213](https://github.com/phstc/shoryuken/pull/213)

- Add FIFO queue support
  - [#272](https://github.com/phstc/shoryuken/issues/272)

- Deprecates initialize_aws
  - [#269](https://github.com/phstc/shoryuken/pull/269)

- [Other miscellaneous updates](https://github.com/phstc/shoryuken/compare/v2.0.11...v2.1.0)

## [v2.0.11] - 2016-07-02

- Same as 2.0.10. Unfortunately 2.0.10 was removed `yanked` by mistake from RubyGems.
  - [#b255bc3](https://github.com/phstc/shoryuken/commit/b255bc3)

## [v2.0.10] - 2016-06-09

- Fix manager #225
  - [#226](https://github.com/phstc/shoryuken/pull/226)

## [v2.0.9] - 2016-06-08

- Fix daemonization broken in #219
  - [#224](https://github.com/phstc/shoryuken/pull/224)

## [v2.0.8] - 2016-06-07

- Fix daemonization
  - [#223](https://github.com/phstc/shoryuken/pull/223)

## [v2.0.7] - 2016-06-06

- Daemonize before loading environment
  - [#219](https://github.com/phstc/shoryuken/pull/219)

- Fix initialization when using rails
  - [#197](https://github.com/phstc/shoryuken/pull/197)

- Improve message fetching
  - [#214](https://github.com/phstc/shoryuken/pull/214)
  - [#f4640d9](https://github.com/phstc/shoryuken/commit/f4640d9)

- Fix hard shutdown if there are some busy workers when signal received
  - [#215](https://github.com/phstc/shoryuken/pull/215)

- Fix `rake console` task
  - [#208](https://github.com/phstc/shoryuken/pull/208)

- Isolate `MessageVisibilityExtender` as new middleware
  - [#199](https://github.com/phstc/shoryuken/pull/190)

- Fail on non-existent queues
  - [#196](https://github.com/phstc/shoryuken/pull/196)

## [v2.0.6] - 2016-04-18

- Fix log initialization introduced by #191
  - [#195](https://github.com/phstc/shoryuken/pull/195)

## [v2.0.5] - 2016-04-17

- Fix log initialization when using `Shoryuken::EnvironmentLoader#load`
  - [#191](https://github.com/phstc/shoryuken/pull/191)

  - Fix `enqueue_at` in the ActiveJob Adapter
  - [#182](https://github.com/phstc/shoryuken/pull/182)

## [v2.0.4] - 2016-02-04

- Add Rails 3 support
  - [#175](https://github.com/phstc/shoryuken/pull/175)

- Allow symbol as a queue name in shoryuken_options
  - [#177](https://github.com/phstc/shoryuken/pull/177)

- Make sure bundler is always updated on Travis CI
  - [#176](https://github.com/phstc/shoryuken/pull/176)

- Add Rails 5 compatibility
  - [#174](https://github.com/phstc/shoryuken/pull/174)

## [v2.0.3] - 2015-12-30

- Allow multiple queues per worker
  - [#164](https://github.com/phstc/shoryuken/pull/164)

- Fix typo
  - [#166](https://github.com/phstc/shoryuken/pull/166)

## [v2.0.2] - 2015-10-27

- Fix warnings that are triggered in some cases with the raise_error matcher
  - [#144](https://github.com/phstc/shoryuken/pull/144)

- Add lifecycle event registration support
  - [#141](https://github.com/phstc/shoryuken/pull/141)

- Allow passing array of messages to send_messages
  - [#140](https://github.com/phstc/shoryuken/pull/140)

- Fix Active Job queue prefixing in Rails apps
  - [#139](https://github.com/phstc/shoryuken/pull/139)

- Enable override the default queue with a :queue option
  - [#147](https://github.com/phstc/shoryuken/pull/147)

## [v2.0.1] - 2015-10-09

- Bump aws-sdk to ~> 2
  - [#138](https://github.com/phstc/shoryuken/pull/138)

## [v2.0.0] - 2015-09-22

- Allow configuration of SQS/SNS endpoints via environment variables
  - [#130](https://github.com/phstc/shoryuken/pull/130)

- Expose queue_name in the message object
  - [#127](https://github.com/phstc/shoryuken/pull/127)

- README updates
  - [#122](https://github.com/phstc/shoryuken/pull/122)
  - [#120](https://github.com/phstc/shoryuken/pull/120)
