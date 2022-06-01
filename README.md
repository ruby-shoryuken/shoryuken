**I'm looking for Shoryuken maintainers, are you interested on helping to maintain Shoryuken? [Join our Slack](https://join.slack.com/t/shoryuken/shared_invite/zt-19xjq3iqc-KmoJ6eU6~qvZNqcLzIrjww)**

# Shoryuken

![Shoryuken](shoryuken.jpg)

Shoryuken _sho-ryu-ken_ is a super-efficient [Amazon SQS](https://aws.amazon.com/sqs/) thread-based message processor.

[![Build Status](https://github.com/ruby-shoryuken/shoryuken/workflows/Specs/badge.svg)](https://github.com/ruby-shoryuken/shoryuken/actions)
[![Code Climate](https://codeclimate.com/github/phstc/shoryuken/badges/gpa.svg)](https://codeclimate.com/github/phstc/shoryuken)

## Key features

- [Rails Active Job](https://github.com/phstc/shoryuken/wiki/Rails-Integration-Active-Job)
- [Queue Load balancing](https://github.com/phstc/shoryuken/wiki/Shoryuken-options#load-balancing)
- [Concurrency per queue](https://github.com/phstc/shoryuken/wiki/Processing-Groups)
- [Long Polling](https://github.com/phstc/shoryuken/wiki/Long-Polling)
- [Batch processing](https://github.com/phstc/shoryuken/wiki/Worker-options#batch)
- [Auto extend visibility timeout](https://github.com/phstc/shoryuken/wiki/Worker-options#auto_visibility_timeout)
- [Exponential backoff](https://github.com/phstc/shoryuken/wiki/Worker-options#retry_intervals)
- [Middleware support](https://github.com/phstc/shoryuken/wiki/Middleware)
- Amazon SQS CLI. See `shoryuken help sqs`

## Requirements

Ruby 2.4 or greater.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'shoryuken'
```

If you are using AWS SDK version 3, please also add this line:

```ruby
gem 'aws-sdk-sqs'
```

The extra gem `aws-sdk-sqs` is required in order to keep Shoryuken compatible with AWS SDK version 2 and 3.

And then execute:

```shell
$ bundle
```

## Usage

Check the [Getting Started](https://github.com/phstc/shoryuken/wiki/Getting-Started) page.

## More Information

For more information check the [wiki page](https://github.com/phstc/shoryuken/wiki).

## Credits

[Mike Perham](https://github.com/mperham), creator of [Sidekiq](https://github.com/mperham/sidekiq), and [everybody who contributed to it](https://github.com/mperham/sidekiq/graphs/contributors). Shoryuken wouldn't exist as it is without those contributions.

## Contributing

1. Fork it ( https://github.com/phstc/shoryuken/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

### Testing

To run all unit specs against the latest dependency vesions, execute

```sh
bundle exec rake spec
```

To run all Rails-related specs against all supported versions of Rails, execute

```sh
bundle exec appraisal rake spec:rails
```

To run integration specs, start a mock SQS server on `localhost:5000`. One such option is [cjlarose/moto-sqs-server](https://github.com/cjlarose/moto-sqs-server). Then execute

```sh
bundle exec rake spec:integration
```
