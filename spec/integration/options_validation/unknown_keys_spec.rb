# frozen_string_literal: true

# This spec tests that `shoryuken start` warns about unknown option keys
# instead of rejecting them.
#
# A mistyped key, globally (`concurency`) or in a group
# (`groups.custom.dealy`), logs a warning naming the key, and the process still
# starts and processes messages. Custom keys kept in the options keep working.
#
# Regression: any key was merged into the options without a check, so a typo
# was silently ignored.

setup_sqs

with_queue_and_dir do |queue, dir|
  marker = File.join(dir, 'processed')
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class UnknownKeysWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body)
        File.write('#{marker}', '')
      end
    end
  RUBY

  config_file = File.join(dir, 'shoryuken.yml')
  File.write(config_file, <<~YAML)
    concurency: 2
    groups:
      custom:
        dealy: 5
        queues:
          - #{queue}
  YAML

  Shoryuken::Client.queues(queue).send_message(message_body: 'hello')

  status, output = run_shoryuken_until('-C', config_file, '-r', boot_file) { File.exist?(marker) }

  assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")
  assert_includes(output, "Unknown option 'concurency' is ignored", "got: #{output}")
  assert_includes(output, "Unknown option 'groups.custom.dealy' is ignored", "got: #{output}")
end
