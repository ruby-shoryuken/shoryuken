# Shoryuken

Shoryuken is an [AWS SQS](https://aws.amazon.com/sqs/) thread based client inspired by [Sidekiq](https://github.com/mperham/sidekiq).

## Why another gem?

> [Wouldn't it be awesome if Sidekiq supported {MongoDB, postgresql, mysql, ...} for persistence?](https://github.com/mperham/sidekiq/wiki/FAQ#wouldnt-it-be-awesome-if-sidekiq-supported-mongodb-postgresql-mysql--for-persistence)

The Sidekiq point to not support other databases is fair enough. So Shoryuken uses the same Sidekiq thread implementation, but for AWS SQS.

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

  shoryuken_options queue: 'my_queue1'

  def perform(sqs_msg, firstname, lastname)
    puts "Hello #{firstname} #{lastname}"

    sqs_msg.delete
  end
end
```

### Enqueue a message

```ruby
HelloWorker.perform_async('Pablo', 'Cantero')
```

## Contributing

1. Fork it ( https://github.com/phstc/shoryuken/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
