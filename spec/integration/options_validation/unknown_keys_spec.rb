# frozen_string_literal: true

# This spec tests that `shoryuken start` warns about unknown option keys
# instead of rejecting them.
#
# Expected behavior: a mistyped key, globally (`concurency`) or in a group
# (`groups.custom.dealy`), logs a warning naming the key, and the process still
# starts and processes messages. Custom keys kept in the options keep working.
#
# Regression: any key was merged into the options without a check, so a typo
# was silently ignored.

require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'fileutils'
require 'timeout'

setup_sqs

BIN = File.expand_path('../../../bin/shoryuken', __dir__)

ENV_VARS = {
  'AWS_ENDPOINT_URL_SQS' => 'http://localhost:9324',
  'AWS_REGION' => 'us-east-1',
  'AWS_ACCESS_KEY_ID' => 'fake',
  'AWS_SECRET_ACCESS_KEY' => 'fake'
}.freeze

dir = Dir.mktmpdir
queue = DT.uuid
create_test_queue(queue)

begin
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

  output = +''
  status = nil
  Open3.popen2e(ENV_VARS, RbConfig.ruby, BIN, 'start', '-C', config_file, '-r', boot_file) do |_in, out, wait|
    reader = Thread.new { out.each_line { |line| output << line } }

    begin
      Timeout.timeout(30) { sleep 0.1 until File.exist?(marker) || !wait.alive? }
    rescue Timeout::Error
      Process.kill('KILL', wait.pid)
    end

    unless File.exist?(marker)
      reader.join
      raise "the message must be processed, got: #{output}"
    end

    Process.kill('TERM', wait.pid)
    status = Timeout.timeout(30) { wait.value }
    reader.join
  end

  assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")
  assert_includes(output, "Unknown option 'concurency' is ignored", "got: #{output}")
  assert_includes(output, "Unknown option 'groups.custom.dealy' is ignored", "got: #{output}")
ensure
  delete_test_queue(queue)
  FileUtils.remove_entry(dir)
end
