# frozen_string_literal: true

# This spec tests that `EnvironmentLoader.setup_options` evaluates ERB in a
# config file in a process that never loads the CLI runner (a script that
# boots Shoryuken itself), and that the queue the ERB names is then processed.
#
# It used to raise `NameError: uninitialized constant
# Shoryuken::EnvironmentLoader::ERB`: only the CLI runner required `erb`.

setup_sqs

with_queue_and_dir do |queue, dir|
  worker_class = Class.new do
    include Shoryuken::Worker

    shoryuken_options auto_delete: true

    def perform(_sqs_msg, body)
      DT[:bodies] << body
    end
  end
  worker_class.get_shoryuken_options['queue'] = queue
  Shoryuken.register_worker(queue, worker_class)

  config = File.join(dir, 'shoryuken.yml')
  File.write(config, <<~YAML)
    concurrency: <%= 1 + 1 %>
    queues:
      - [<%= ENV['ERB_OUTSIDE_CLI_QUEUE'] %>, 2]
  YAML
  ENV['ERB_OUTSIDE_CLI_QUEUE'] = queue

  Shoryuken::EnvironmentLoader.setup_options(config_file: config).load

  assert_equal(2, Shoryuken.options[:concurrency])
  assert_equal([queue, queue], Shoryuken.groups['default'][:queues])

  Shoryuken::Client.queues(queue).send_message(message_body: 'erb')

  poll_queues_until { DT[:bodies].any? }

  assert_equal(['erb'], DT[:bodies])
end
