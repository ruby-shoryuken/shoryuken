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
