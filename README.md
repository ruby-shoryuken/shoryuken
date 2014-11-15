# Shoryuken

![](shoryuken.jpg)

Shoryuken _sho-ryu-ken_ is a super efficient [AWS SQS](https://aws.amazon.com/sqs/) thread based message processor.

[![Build Status](https://travis-ci.org/phstc/shoryuken.svg)](https://travis-ci.org/phstc/shoryuken)

## Key features

### Load balancing

Yeah, Shoryuken load balances the messages consumption!

Given this configuration:

```yaml
concurrency: 25,
delay: 25,
queues:
  - [high_priority, 6]
  - [default, 2]
  - [low_priority, 1]
```

And supposing all the queues are full of messages, the configuration above will make Shoryuken to process `high_priority` 3 times more than `default` and 6 times more than `low_priority`,
splitting the work among the `concurrency: 25` available processors.

If `high_priority` gets empty, Shoryuken will keep using the 25 processors, but only to process `default` (2 times more than `low_priority`) and `low_priority`.

If `high_priority` receives a new message, Shoryuken will smoothly increase back the `high_priority` weight one by one until it reaches the weight of 6 again, which is the maximum configured for `high_priority`.

If all queues get empty, all processors will be changed to the waiting state and the queues will be checked every `delay: 25`. If any queue receives a new message, Shoryuken will start processing again. [Check the delay option documentation for more information](https://github.com/phstc/shoryuken/wiki/Shoryuken-options#delay).


### Fetch in batches

To be even more performance and cost efficient, Shoryuken fetches SQS messages in batches, so a single SQS request can fetch up to 10 messages.

## Installation

Add this line to your application's Gemfile:

    gem 'shoryuken'

Or to get the latest updates:

    gem 'shoryuken', github: 'phstc/shoryuken', branch: 'master'

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
  # shoryuken_options queue: ->{ "#{ENV['environment']_default" }

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

### Midleware

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

### Configuration

Sample configuration file `shoryuken.yml`.

```yaml
aws:
  access_key_id:      ...       # or <%= ENV['AWS_ACCESS_KEY_ID'] %>
  secret_access_key:  ...       # or <%= ENV['AWS_SECRET_ACCESS_KEY'] %>
  region:             us-east-1 # or <%= ENV['AWS_REGION'] %>
  receive_message:              # See http://docs.aws.amazon.com/AWSRubySDK/latest/AWS/SQS/Queue.html#receive_message-instance_method
    # wait_time_seconds: N      # The number of seconds to wait for new messages when polling. Defaults to the #wait_time_seconds defined on the queue
    attributes:
      - receive_count
      - sent_at
concurrency: 25,  # The number of allocated threads to process messages. Default 25
delay: 25,        # The delay in seconds to pause a queue when it's empty. Default 0
queues:
  - [high_priority, 6]
  - [default, 2]
  - [low_priority, 1]
```

### Rails Integration

You can tell Shoryuken to load your Rails application by passing the `-R` or `--rails` flag to the "shoryuken" command.

If you load Rails, and assuming your workers are located in the `app/workers` directory, they will be auto-loaded. This means you don't need to require them explicitly with `-r`.

This feature works for Rails 4+, but needs to be confirmed for older versions.

### Start Shoryuken

```shell
bundle exec shoryuken -r worker.rb -C shoryuken.yml
```

Other options:

```bash
shoryuken --help

shoryuken [options]
    -c, --concurrency INT            Processor threads to use
    -d, --daemon                     Daemonize process
    -q, --queue QUEUE[,WEIGHT]...    Queues to process with optional weights
    -r, --require [PATH|DIR]         Location of the worker
    -C, --config PATH                Path to YAML config file
    -R, --rails                      Attempts to load the containing Rails project
    -L, --logfile PATH               Path to writable logfile
    -P, --pidfile PATH               Path to pidfile
    -v, --verbose                    Print more verbose output
    -V, --version                    Print version and exit
    -h, --help                       Show help
    ...
```


## More Information

Please check the [Shoryuken Wiki](https://github.com/phstc/shoryuken/wiki).

## Credits

[Mike Perham](https://github.com/mperham), creator of [Sidekiq](https://github.com/mperham/sidekiq), and [everybody who contributed to it](https://github.com/mperham/sidekiq/graphs/contributors). Shoryuken wouldn't exist as it is without those contributions.

## Contributing

1. Fork it ( https://github.com/phstc/shoryuken/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
