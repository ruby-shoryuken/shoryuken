# frozen_string_literal: true

# This spec tests lifecycle events with several handlers per event in `shoryuken start`.
#
# The handlers of an event run in registration order, except quiet and shutdown, whose handlers run in reverse. A
# raising handler is logged as a warning and the next handler of the event still runs. `Shoryuken.on` raises
# InvalidEventError for an event that is not a Symbol or not a known event.

setup_sqs

with_queue_and_dir do |queue, dir|
  boot_file = File.join(dir, 'boot.rb')
  File.write(boot_file, <<~RUBY)
    class SeveralHandlersWorker
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(_sqs_msg, _body); end
    end

    Shoryuken.on(:startup) { raise 'first startup handler failed' }
    Shoryuken.on(:startup) { Shoryuken.logger.info('lifecycle handler: startup second') }

    %i[quiet shutdown stopped].each do |event|
      %w[first second].each do |handler|
        Shoryuken.on(event) { Shoryuken.logger.info("lifecycle handler: \#{event} \#{handler}") }
      end
    end
  RUBY

  status, output = run_shoryuken_until('-q', queue, '-r', boot_file, signal: 'USR1') do |log|
    log.include?('lifecycle handler: startup second')
  end

  assert(status.success?, "the process must exit with status 0, got #{status.inspect}: #{output}")
  assert_includes(output, 'Received USR1, will soft shutdown', "got: #{output}")

  assert_equal(
    [
      'startup second',
      'quiet second',
      'quiet first',
      'shutdown second',
      'shutdown first',
      'stopped first',
      'stopped second'
    ],
    output.scan(/lifecycle handler: (\w+ \w+)/).flatten,
    "startup and stopped handlers must run in registration order, quiet and shutdown in reverse, got: #{output}"
  )

  warning = output.lines.find { |line| line.include?('RuntimeError: first startup handler failed') }
  assert(warning&.include?('WARN'), "the raising handler must be logged as a warning, got: #{output}")
  assert(
    output.index('first startup handler failed') < output.index('lifecycle handler: startup second'),
    "the raising handler must run before the second startup handler, got: #{output}"
  )
end

{ 'startup' => 'Symbols only please: startup', bogus: 'Invalid event name: bogus' }.each do |event, message|
  error = raised_error(Shoryuken::Errors::InvalidEventError) { Shoryuken.on(event) {} }
  assert_equal(message, error&.message, "Shoryuken.on(#{event.inspect}) must raise InvalidEventError")
end
