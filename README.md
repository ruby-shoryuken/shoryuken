# Shoryuken

![](shoryuken.jpg)

Shoryuken _sho-ryu-ken_ is a super-efficient [Amazon SQS](https://aws.amazon.com/sqs/) thread-based message processor.

[![Build Status](https://travis-ci.org/phstc/shoryuken.svg)](https://travis-ci.org/phstc/shoryuken)
[![Code Climate](https://codeclimate.com/github/phstc/shoryuken/badges/gpa.svg)](https://codeclimate.com/github/phstc/shoryuken)

## Key features

- [Rails Active Job support](https://github.com/phstc/shoryuken/wiki/Rails-Integration-Active-Job)
- Queue Load balancing
- Concurrency per queue
- Long polling
- Batch processing
- [Auto extend visibility timeout](https://github.com/phstc/shoryuken/wiki/Worker-options#auto_visibility_timeout)
- Exponential backoff
- Middleware support
- Native support for [Honeybadger](https://www.honeybadger.io/) and [Airbrake](https://airbrake.io/)
- Amazon SQS CLI

## Requirements

Ruby 2.0 or greater.

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

Create a worker:

```ruby
class HelloWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'hello', auto_delete: true

  def perform(sqs_msg, name)
    puts "Hello, #{name}"
  end
end
```

Create a create:

```shell
bundle exec shoryuken sqs create hello
```

Start Shoryuken:

```shell
bundle exec shoryuken -q my-queue -r ./hello_worker.rb
```

Enqueue a message:

```ruby
HelloWorker.perform_async('Ken')
```

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
