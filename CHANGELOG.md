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
