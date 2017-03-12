# Shoryuken

![](shoryuken.jpg)

Shoryuken _sho-ryu-ken_ is a super-efficient [AWS SQS](https://aws.amazon.com/sqs/) thread-based message processor.

[![Build Status](https://travis-ci.org/phstc/shoryuken.svg)](https://travis-ci.org/phstc/shoryuken)
[![Code Climate](https://codeclimate.com/github/phstc/shoryuken/badges/gpa.svg)](https://codeclimate.com/github/phstc/shoryuken)

## Key features

### Load balancing

Yeah, Shoryuken load balances the messages consumption!

Given this configuration:

```yaml
concurrency: 25
delay: 25
queues:
  - [high_priority, 6]
  - [normal_priority, 2]
  - [low_priority, 1]
```

And supposing all the queues are full of messages, the configuration above will make Shoryuken to process `high_priority` 3 times more than `normal_priority` and 6 times more than `low_priority`,
splitting the work load among all available processors `concurrency: 25` .

If `high_priority` gets empty, Shoryuken will keep using the 25 processors, but only to process `normal_priority` and `low_priority`.

If `high_priority` receives a new message, Shoryuken will smoothly increase back its weight one by one until it reaches the weight of 6 again.

[If a queue gets empty, Shoryuken will pause checking it for `delay: 25`](https://github.com/phstc/shoryuken/wiki/Shoryuken-options#delay).


### Fetch in batches

To be even more performant and cost effective, Shoryuken fetches SQS messages in batches, so a single SQS request can fetch up to 10 messages.

## Requirements

Ruby 2.0 or greater.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'shoryuken'
```

Or to get the latest updates:

```ruby
gem 'shoryuken', github: 'phstc/shoryuken', branch: 'master'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install shoryuken

## Usage

### Worker class

```ruby
class MyWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'default', auto_delete: true
  # shoryuken_options queue: ->{ "#{ENV['environment']}_default" }

  # shoryuken_options body_parser: :json
  # shoryuken_options body_parser: ->(sqs_msg){ REXML::Document.new(sqs_msg.body) }
  # shoryuken_options body_parser: JSON

  def perform(sqs_msg, body)
    puts body
  end
end
```

[Check the Worker options documention](https://github.com/phstc/shoryuken/wiki/Worker-options).

### Sending a message

[Check the Sending a message documentation](https://github.com/phstc/shoryuken/wiki/Sending-a-message)

### Middleware

```ruby
class MyMiddleware
  def call(worker_instance, queue, sqs_msg, body)
    puts 'Before work'
    yield
    puts 'After work'
  end
end
```

[Check the Middleware documentation](https://github.com/phstc/shoryuken/wiki/Middleware).

### Shoryuken Configuration

Sample configuration file `shoryuken.yml`.

```yaml
concurrency: 25  # The number of allocated threads to process messages. Default 25
delay: 25        # The delay in seconds to pause a queue when it's empty. Default 0
queues:
  - [high_priority, 6]
  - [normal_priority, 2]
  - [low_priority, 1]
```

#### AWS Configuration

[Check the Configure AWS Client documentation](https://github.com/phstc/shoryuken/wiki/Configure-the-AWS-Client)

### Rails Integration

[Check the Rails Integration Active Job documention](https://github.com/phstc/shoryuken/wiki/Rails-Integration-Active-Job).

### Start Shoryuken

```shell
bundle exec shoryuken -r worker.rb -C shoryuken.yml
```

For other options check `bundle exec shoryuken help start`

#### SQS commands

Check also some available SQS commands `bundle exec shoryuken help sqs`, such as:

- `ls` list queues
- `mv` move messages from one queue to another
- `dump` dump messages from a queue into a JSON lines file
- `requeue` requeue messages from a dump file

## More Information

For more information on advanced topics such as signals (shutdown), ActiveJob integration, and so on please check the [Shoryuken Wiki](https://github.com/phstc/shoryuken/wiki).

## Credits

[Mike Perham](https://github.com/mperham), creator of [Sidekiq](https://github.com/mperham/sidekiq), and [everybody who contributed to it](https://github.com/mperham/sidekiq/graphs/contributors). Shoryuken wouldn't exist as it is without those contributions.

## Contributing

1. Fork it ( https://github.com/phstc/shoryuken/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
