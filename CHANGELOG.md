## [v2.0.7] -

- Daemonize before loading environment
 - [#219] https://github.com/phstc/shoryuken/pull/219

- Fix initialization when using rails
 - [#197] https://github.com/phstc/shoryuken/pull/197

- Improve message fetching
 - https://github.com/phstc/shoryuken/pull/214 and https://github.com/phstc/shoryuken/commit/f4640d97950c1783a061195855d93994725ed64a

- Fix hard shutdown if there are some busy workers when signal received
 - [#215] https://github.com/phstc/shoryuken/pull/215

- Fix `rake console` task
 - [#208] https://github.com/phstc/shoryuken/pull/208

- Isolate `MessageVisibilityExtender` as new middleware
 - [#199] https://github.com/phstc/shoryuken/pull/190

- Fail on non-existent queues
 - [#196] https://github.com/phstc/shoryuken/pull/196

## [v2.0.6] -

- Fix log initialization introduced by #191
 - [#195](https://github.com/phstc/shoryuken/pull/195)

## [v2.0.5] -

- Fix log initialization when using `Shoryuken::EnvironmentLoader#load`
 - [#191](https://github.com/phstc/shoryuken/pull/191)

 - Fix `enqueue_at` in the ActiveJob Adapter
 - [#182](https://github.com/phstc/shoryuken/pull/182)

## [v2.0.4] -

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
