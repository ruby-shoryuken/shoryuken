# Shoryuken

Shoryuken _sho-ryu-ken_ is a super-efficient [Amazon SQS](https://aws.amazon.com/sqs/) thread-based message processor.

[![Build Status](https://github.com/ruby-shoryuken/shoryuken/workflows/Specs/badge.svg)](https://github.com/ruby-shoryuken/shoryuken/actions)
[![Join the chat at https://slack.shoryuken.io](https://raw.githubusercontent.com/karafka/misc/master/slack.svg)](https://slack.shoryuken.io)

## Key features

- [Rails Active Job](https://github.com/ruby-shoryuken/shoryuken/wiki/Rails-Integration-Active-Job)
- [Queue Load balancing](https://github.com/ruby-shoryuken/shoryuken/wiki/Shoryuken-options#load-balancing)
- [Concurrency per queue](https://github.com/ruby-shoryuken/shoryuken/wiki/Processing-Groups)
- [Long Polling](https://github.com/ruby-shoryuken/shoryuken/wiki/Long-Polling)
- [Batch processing](https://github.com/ruby-shoryuken/shoryuken/wiki/Worker-options#batch)
- [Auto extend visibility timeout](https://github.com/ruby-shoryuken/shoryuken/wiki/Worker-options#auto_visibility_timeout)
- [Exponential backoff](https://github.com/ruby-shoryuken/shoryuken/wiki/Worker-options#retry_intervals)
- [Middleware support](https://github.com/ruby-shoryuken/shoryuken/wiki/Middleware)
- Amazon SQS CLI. See `shoryuken help sqs`

## Requirements

Ruby 3.0 or greater.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'shoryuken'
```

And then execute:

```shell
$ bundle
```

## Usage

Check the [Getting Started](https://github.com/ruby-shoryuken/shoryuken/wiki/Getting-Started) page.

## More Information

For more information check the [wiki page](https://github.com/ruby-shoryuken/shoryuken/wiki).

## Credits

[Mike Perham](https://github.com/mperham), creator of [Sidekiq](https://github.com/mperham/sidekiq), and [everybody who contributed to it](https://github.com/mperham/sidekiq/graphs/contributors). Shoryuken wouldn't exist as it is without those contributions.

## Contributing

1. Fork it ( https://github.com/ruby-shoryuken/shoryuken/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

### Testing

To run all unit specs against the latest dependency versions, execute

```sh
bundle exec rake spec
```

To run integration specs (including Rails tests), start LocalStack and run:

```sh
docker compose up -d
bundle exec rake spec:integration
```

### To release a new version

Compare latest tag with HEAD:

```sh
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

then update CHANGELOG.md.

Update version in `lib/shoryuken/version.rb` with the appropriate version number [SEMVER](https://semver.org/).

then run:

```sh
bundle exec rake release
```
