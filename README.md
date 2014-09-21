# Shoryuken

![](shoryuken.jpg)

Shoryuken is a super efficient [AWS SQS](https://aws.amazon.com/sqs/) thread based processor inspired by [Sidekiq](https://github.com/mperham/sidekiq).

## Key features

### Load balancing

Yeah, Shoryuken load balances the messages consumption, for example:

Given this configuration:

```yaml
concurrency: 25,
delay: 60,
queues:
  - [shoryuken, 6]
  - [uppercut, 2]
  - [sidekiq, 1]
```

And supposing all the queues are full of messages, the configuration above will make Shoryuken to process "shoryuken" 3 times more than "uppercut" and 6 times more than "sidekiq",
splitting the work among the 25 available processors.

If the “shoryuken" queue gets empty, Shoryuken will keep using the 25 processors, but only to process “uppercut” (2 times more than “sidekiq”) and “sidekiq”.

If the “shoryuken” queue gets a new message, Shoryuken will smoothly increase back the "shoryuken" weight one by one until it reaches the weight of 5 again.

If all queues get empty, all processors will be changed to the waiting state and the queues will be checked every `delay: 60`. If any queue gets a new message, Shoryuken will bring back the processors one by one to the ready state.

### Fetch in batches

To be more efficient (performance/cost), Shoryuken retrieves SQS messages in batches, the batch size is based on `ready_processors > 10 ? 10 : ready_processors`, [SQS limits the batch by 10](http://docs.aws.amazon.com/AWSRubySDK/latest/AWS/SQS/Queue.html#receive_message-instance_method).

## Why another gem?

> [Wouldn't it be awesome if Sidekiq supported {MongoDB, postgresql, mysql, ...} for persistence?](https://github.com/mperham/sidekiq/wiki/FAQ#wouldnt-it-be-awesome-if-sidekiq-supported-mongodb-postgresql-mysql--for-persistence)
> Not really....
> If you want a queueing system that uses X, use a queuing system that uses X!...

The Sidekiq point to not support other databases is fair enough. Shoryuken uses the same Sidekiq thread implementation, but for AWS SQS.

## Resque compatible?

Shoryuken isn't Resque compatible, it passes the [original SQS message](http://docs.aws.amazon.com/AWSRubySDK/latest/AWS/SQS/ReceivedMessage.html) to the workers.

## Installation

Add this line to your application's Gemfile:

    gem 'shoryuken'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install shoryuken

## Usage

### Worker class

```ruby
class HelloWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'hello', auto_delete: true
  # shoryuken_options queue: ->{ "#{ENV['environment']_hello" }, auto_delete: true

  def perform(sqs_msg)
    puts "Hello #{sqs_msg.body}"
  end
end
```

### Sending a message

```ruby
Shoryuken::Client.queues('hello').send_message('Pablo')
```

### Configuration

Sample configuration file `shoryuken.yml`.

```yaml
aws:
  access_key_id:      ...
  secret_access_key:  ...
  region:             us-east-1
  receive_message:
    attributes:
      - receive_count
      - sent_at
delay: 25
timeout: 8
queues:
  - [shoryuken, 5]
  - [uppercut, 2]
  - [sidekiq, 1]
```

### Start Shoryuken

```shell
bundle exec shoryuken -r worker.rb -C shoryuken.yml
```

### Middleware

```ruby
class MyServerHook
  def call(worker_instance, queue, sqs_msg)
    puts 'Before work'
    yield
    puts 'After work'
  end
end

Shoryuken.configure_server do |config|
  config.server_middleware do |chain|
    chain.add MyServerHook
    # chain.remove MyServerHook
  end
end
```

## Contributing

1. Fork it ( https://github.com/phstc/shoryuken/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
