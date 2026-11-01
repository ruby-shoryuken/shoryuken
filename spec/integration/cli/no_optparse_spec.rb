# frozen_string_literal: true

# This spec tests which libraries `shoryuken` loads before it requires user code.
#
# `optparse` is not loaded, so `OptionParser` is not defined
# in a file passed with `-r`.

setup_sqs

with_queue_and_dir do |queue, dir|
  marker = File.join(dir, 'option_parser')
  worker_file = File.join(dir, 'worker.rb')
  File.write(worker_file, <<~RUBY)
    File.write('#{marker}', defined?(OptionParser).inspect)

    class NoOptparseWorker
      include Shoryuken::Worker
      shoryuken_options queue: '#{queue}'
      def perform(_sqs_msg, _body); end
    end
  RUBY

  status, output = run_shoryuken_command_until_exit('check', '-q', queue, '-r', worker_file)
  assert_equal(0, status.exitstatus, output)
  assert_equal('nil', File.read(marker))
end
