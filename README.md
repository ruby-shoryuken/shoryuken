# Shoryuken

![](shoryuken.jpg)

Shoryuken _sho-ryu-ken_ is a super efficient [AWS SQS](https://aws.amazon.com/sqs/) thread based message processor.

## Key features

### Load balancing

Yeah, Shoryuken load balances the messages consumption, for example:

Given this configuration:

```yaml
concurrency: 25,
delay: 25,
queues:
  - [shoryuken, 6]
  - [uppercut, 2]
  - [sidekiq, 1]
```

And supposing all the queues are full of messages, the configuration above will make Shoryuken to process "shoryuken" 3 times more than "uppercut" and 6 times more than "sidekiq",
splitting the work among the 25 available processors.

If the "shoryuken" queue gets empty, Shoryuken will keep using the 25 processors, but only to process "uppercut" (2 times more than "sidekiq") and "sidekiq".

If the "shoryuken" queue gets a new message, Shoryuken will smoothly increase back the "shoryuken" weight one by one until it reaches the weight of 5 again.

If all queues get empty, all processors will be changed to the waiting state and the queues will be checked every `delay: 25`. If any queue gets a new message, Shoryuken will bring back the processors one by one to the ready state.

### Fetch in batches

To be even more performance and cost efficient, Shoryuken fetches SQS messages in batches.

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
concurrency: 25,
delay: 25,
timeout: 8
queues:
  - [shoryuken, 6]
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

## Credits

[Mike Perham](https://github.com/mperham), creator of [Sidekiq](https://github.com/mperham/sidekiq), and [everybody who contributed to it](https://github.com/mperham/sidekiq/graphs/contributors). Shoryuken wouldn't exist as it is without those contributions.

## Contributing

1. Fork it ( https://github.com/phstc/shoryuken/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
