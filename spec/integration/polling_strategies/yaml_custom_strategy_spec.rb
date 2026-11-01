# frozen_string_literal: true

# This spec tests that a custom polling strategy class named in a YAML config
# file (`-C`) is the one `shoryuken start` uses to pick the queues it fetches.
#
# - With `polling_strategy: <Class>` at the top level and with it inside a
#   `groups:` entry, the process boots and the custom strategy is asked for the
#   next queue
# - Only the queue the strategy returns is fetched: its message is processed,
#   while the message in the queue it never returns stays in SQS
#
# It used to reject the class name a YAML file gives as a String, failing at
# boot with "is not a valid polling_strategy".
#
# Regression: #675, #925

setup_sqs

def expect_custom_strategy_used(name, config)
  with_queue_and_dir do |skipped_queue, dir|
    with_queue_and_dir do |polled_queue, _|
      expect_only_polled_queue_fetched(dir, name, config, skipped_queue, polled_queue)
    end
  end
end

def expect_only_polled_queue_fetched(dir, name, config, skipped_queue, polled_queue)
  polls = File.join(dir, "#{name}.polls")
  processed = File.join(dir, "#{name}.processed")
  boot_file = File.join(dir, "#{name}_boot.rb")
  File.write(boot_file, <<~RUBY)
    class LastQueueOnlyStrategy < Shoryuken::Polling::BaseStrategy
      def initialize(queues, _delay = nil)
        @queue = queues.last
      end

      def next_queue
        File.write('#{polls}', "\#{@queue}\\n", mode: 'a')
        Shoryuken::Polling::QueueConfiguration.new(@queue, {})
      end

      def messages_found(_queue, _messages_found); end

      def active_queues
        [[@queue, 1]]
      end
    end

    class YamlCustomStrategyWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{polled_queue}', auto_delete: true

      def perform(_sqs_msg, body)
        File.write('#{processed}', "\#{body}\\n", mode: 'a')
      end
    end

    Shoryuken.register_worker('#{skipped_queue}', YamlCustomStrategyWorker)
  RUBY

  config_file = File.join(dir, "#{name}.yml")
  File.write(config_file, format(config, skipped_queue: skipped_queue, polled_queue: polled_queue))

  Shoryuken::Client.queues(skipped_queue).send_message(message_body: 'skipped')
  Shoryuken::Client.queues(polled_queue).send_message(message_body: 'polled')

  # Several polls after the processed message give the skipped queue a chance to be fetched
  status, output = run_shoryuken_until('-r', boot_file, '-C', config_file) do
    File.exist?(processed) && File.exist?(polls) && File.readlines(polls).size >= 5
  end

  assert(status.success?, "#{name}: the process must exit cleanly, got #{status.inspect}: #{output}")
  assert_equal(["#{polled_queue}\n"], File.readlines(polls).uniq, "#{name}: the strategy must return only #{polled_queue}")
  assert_equal(["polled\n"], File.readlines(processed), "#{name}: only the polled queue must be fetched: #{output}")
  assert_equal(0, queue_size(polled_queue), "#{name}: the polled message must be deleted")
  assert_equal(1, queue_size(skipped_queue), "#{name}: the skipped queue must not be fetched")
end

# --- top-level polling_strategy ---
expect_custom_strategy_used('top_level', <<~YAML)
  polling_strategy: LastQueueOnlyStrategy
  queues:
    - %<skipped_queue>s
    - %<polled_queue>s
YAML

# --- polling_strategy of a processing group ---
expect_custom_strategy_used('group', <<~YAML)
  groups:
    custom:
      concurrency: 1
      polling_strategy: LastQueueOnlyStrategy
      queues:
        - %<skipped_queue>s
        - %<polled_queue>s
YAML
