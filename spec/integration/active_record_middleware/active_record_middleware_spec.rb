# frozen_string_literal: true

# This spec tests the ActiveRecord middleware functionality.
# The middleware clears database connections after each message is processed.

setup_localstack

queue_name = DT.queue
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

# Mock ActiveRecord module to track connection clearing
module ActiveRecord
  VERSION = Gem::Version.new('7.2.0')

  def self.version
    VERSION
  end

  class Base
    class << self
      attr_accessor :connections_cleared

      def connection_handler
        @connection_handler ||= ConnectionHandler.new
      end
    end

    self.connections_cleared = []
  end

  class ConnectionHandler
    def clear_active_connections!(scope)
      ActiveRecord::Base.connections_cleared << { scope: scope, time: Time.now }
    end
  end
end

# Add the ActiveRecord middleware to the chain
require 'shoryuken/middleware/server/active_record'
Shoryuken.configure_server do |config|
  config.server_middleware do |chain|
    chain.add Shoryuken::Middleware::Server::ActiveRecord
  end
end

worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options auto_delete: true, batch: false

  def perform(sqs_msg, body)
    DT[:processed] << { message_id: sqs_msg.message_id, body: body }
  end
end

worker_class.get_shoryuken_options['queue'] = queue_name
Shoryuken.register_worker(queue_name, worker_class)

# Clear any prior connection clearing records
ActiveRecord::Base.connections_cleared.clear

# Send multiple messages
3.times { |i| Shoryuken::Client.queues(queue_name).send_message(message_body: "ar-test-#{i}") }

sleep 1

poll_queues_until { DT[:processed].size >= 3 }

# Verify all messages were processed
assert_equal(3, DT[:processed].size)

# Verify ActiveRecord connections were cleared after each message
# The middleware should have called clear_active_connections! for each message
assert(
  ActiveRecord::Base.connections_cleared.size >= 3,
  "ActiveRecord connections should be cleared after each message (cleared #{ActiveRecord::Base.connections_cleared.size} times)"
)

# Verify the :all scope was used (Rails 7.1+ behavior)
ActiveRecord::Base.connections_cleared.each do |record|
  assert_equal(:all, record[:scope], 'Should use :all scope for Rails 7.1+')
end
