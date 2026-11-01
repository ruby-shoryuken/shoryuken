# frozen_string_literal: true

# This spec tests the full sequence of lifecycle events that `shoryuken start` fires while it processes a message and
# stops on USR1 with that message still in flight.
#
# `startup` fires once, first. The group then reports its utilization (busy 0), dispatches from the queue (the
# payload names it) and reports busy 1 for the message. USR1 then fires quiet and shutdown; the group reports busy
# 0 when the in-flight message is done, and stopped fires after it, as the last event. Each of quiet, shutdown and
# stopped fires once.

def parse_events(log)
  log.scan(/lifecycle event: (\w+) (\{.*\})$/).map { |event, payload| [event, JSON.parse(payload)] }
end

setup_sqs

with_queue_and_dir do |queue, dir|
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    require 'json'

    class FullEventSequenceWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body)
        sleep 2
      end
    end

    %i[startup dispatch utilization_update quiet shutdown stopped].each do |event|
      Shoryuken.on(event) { |payload| Shoryuken.logger.info("lifecycle event: \#{event} \#{JSON.generate(payload)}") }
    end
  RUBY

  Shoryuken::Client.queues(queue).send_message(message_body: 'lifecycle')

  idle = { 'group' => 'default', 'max_processors' => 2, 'busy_processors' => 0 }
  busy = idle.merge('busy_processors' => 1)

  status, output = run_shoryuken_until('-q', queue, '-c', '2', '-r', boot_file, signal: 'USR1') do |log|
    parse_events(log).include?(['utilization_update', busy])
  end

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(output, 'Received USR1, will soft shutdown', "got: #{output}")

  events = parse_events(output)
  dispatches, others = events.partition { |event, _payload| event == 'dispatch' }

  assert_equal(
    [
      ['startup', {}],
      ['utilization_update', idle],
      ['utilization_update', busy],
      ['quiet', {}],
      ['shutdown', {}],
      ['utilization_update', idle],
      ['stopped', {}]
    ],
    others,
    "the non-dispatch events must fire in the documented order and count, got: #{output}"
  )

  refute(dispatches.empty?, "dispatch must fire, got: #{output}")
  assert_equal([{ 'queue_name' => queue }], dispatches.map(&:last).uniq, "dispatch must name the queue, got: #{output}")

  first_dispatch = events.index { |event, _payload| event == 'dispatch' }
  group_started = events.index(['utilization_update', idle])
  message_assigned = events.index(['utilization_update', busy])
  assert(
    group_started < first_dispatch && first_dispatch < message_assigned,
    "the first dispatch must come after the group starts and before the message is processed, got: #{output}"
  )
  assert_equal('stopped', events.last.first, "stopped must be the last event, got: #{output}")
end
