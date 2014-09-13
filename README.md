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

  shoryuken_options queue: 'hello', auto_delete: true

  def perform(sqs_msg)
    puts "Hello #{sqs_msg.body}"
  end
end
```

### Enqueue a message

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
    wait_time_seconds: 20
    max_number_of_messages: 1
    attributes:
      - receive_count
      - sent_at
queues:
  - shoryuken

```

### Start Shoryuken

```shell
bundle exec shoryuken -r worker.rb -c shoryuken.yml
```


## Contributing

1. Fork it ( https://github.com/phstc/shoryuken/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
