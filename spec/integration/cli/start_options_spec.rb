# frozen_string_literal: true

# This spec tests how `bin/shoryuken` parses the options of `start` and `check`, and its `help` and `version`
# commands.
#
# Each option reaches `Shoryuken.options` in its short and long form with its value type: `-c`, `-t` and `-D` as
# numbers, `-q` as the values up to the next switch, `-r`, `-L`, `-P` and `-C`/`--config-file` as strings, `-v` and
# `-d` as booleans with `--no-`. With no command `shoryuken` runs `start`. Bad input prints the error and exits with
# status 1; `help`, `-h` and `--help` print the commands or the options of one command and exit with status 0.

setup_sqs

KEYS = %i[concurrency timeout delay queues verbose daemon logfile pidfile config_file].freeze

def parsed_options(dir, queue, *args)
  marker = File.join(dir, 'options.json')
  worker_file = File.join(dir, 'worker.rb')
  File.write(worker_file, <<~RUBY)
    require 'json'
    File.write('#{marker}', JSON.dump(Shoryuken.options.slice(*#{KEYS.inspect})))

    class StartOptionsWorker
      include Shoryuken::Worker
      shoryuken_options queue: '#{queue}'
      def perform(_sqs_msg, _body); end
    end
  RUBY

  status, output = run_shoryuken_command_until_exit('check', *args, '-r', worker_file)
  assert_equal(0, status.exitstatus, "check #{args.join(' ')} must exit 0, got: #{output}")

  [JSON.parse(File.read(marker), symbolize_names: true), output]
end

def assert_rejected(args, message)
  status, output = run_shoryuken_command_until_exit(*args)
  assert_equal(1, status.exitstatus, "#{args.join(' ')} must exit 1, got: #{output}")
  assert_includes(output, message)
  refute(output.include?('.rb:'), "must not print a backtrace, got: #{output}")
end

with_queue_and_dir do |queue, dir|
  config = File.join(dir, 'shoryuken.yml')
  File.write(config, "concurrency: 7\n")
  logfile = File.join(dir, 'shoryuken.log')
  pidfile = File.join(dir, 'shoryuken.pid')

  options, output = parsed_options(
    dir, queue,
    '-c', '3', '-t', '7.5', '-D', '2', '-q', "#{queue},2", queue, '-v', '-d', '-L', logfile, '-P', pidfile
  )
  assert_equal(
    {
      concurrency: 3, timeout: 7.5, delay: 2, queues: [[queue, '2'], [queue]], verbose: true, daemon: true,
      logfile: logfile, pidfile: pidfile
    },
    options.compact
  )
  refute(output.include?('[DEPRECATED]'), "got: #{output}")

  options, = parsed_options(
    dir, queue,
    '--concurrency=4', '--timeout', '1', '--delay=0.5', '--queues', queue, '--no-verbose', '--logfile', logfile,
    '--pidfile', pidfile, '--no-daemon'
  )
  assert_equal(
    {
      concurrency: 4, timeout: 1, delay: 0.5, queues: [[queue]], verbose: false, daemon: false, logfile: logfile,
      pidfile: pidfile
    },
    options.compact
  )

  options, output = parsed_options(dir, queue, '-q', queue, '-C', config)
  assert_equal([config, 7], [options[:config_file], options[:concurrency]])
  refute(output.include?('[DEPRECATED]'), "got: #{output}")

  %w[--config-file --config_file].each do |switch|
    options, output = parsed_options(dir, queue, '-q', queue, switch, config, '-c=5')
    assert_equal([config, 5], [options[:config_file], options[:concurrency]])
    assert_includes(output, '[DEPRECATED] Please use --config instead of --config-file')
  end

  options, = parsed_options(dir, queue, '-vdq', queue, '-L', logfile)
  assert_equal([true, true, [[queue]]], options.values_at(:verbose, :daemon, :queues), 'a cluster must end with -q')

  options, = parsed_options(dir, queue, '-q', queue, '-P', '-d', '-L', logfile)
  assert_equal(['pidfile', true], options.values_at(:pidfile, :daemon), '-P with no value must not take -d')
end

# --- start is the default command ---
assert_rejected(%w[-c abc], %(Expected numeric value for '--concurrency'; got "abc"))
assert_rejected(%w[start -t x], %(Expected numeric value for '--timeout'; got "x"))
assert_rejected(%w[start -q], "No value provided for option '--queues'")
assert_rejected(%w[start -c -v], "No value provided for option '--concurrency'")
assert_rejected(%w[check -r], '[FAIL] cannot load such file -- require')
assert_rejected(%w[start -d], "[FAIL] You should set a logfile if you're going to daemonize")
assert_rejected(%w[start -qa], "No value provided for option '--queues'")
assert_rejected(%w[start -qdefault,2], 'Unknown switches "-qdefault,2"')
assert_rejected(%w[start --conc 2], %(Unknown switches "--conc"\nDid you mean?  "--config"))
assert_rejected(%w[STart], %(Could not find command "STart".\nDid you mean?  "start"))

# --- help ---
[%w[help], %w[-h], %w[--help], %w[-?]].each do |args|
  status, output = run_shoryuken_command_until_exit(*args)
  assert_equal(0, status.exitstatus, "#{args.join(' ')} must exit 0, got: #{output}")
  %w[check help sqs start version].each do |command|
    assert(output.match?(/^  shoryuken #{command}\b.*# /), "#{args.join(' ')} must list #{command}, got: #{output}")
  end
end

[%w[help start], %w[start -h], %w[check --help]].each do |args|
  status, output = run_shoryuken_command_until_exit(*args)
  assert_equal(0, status.exitstatus, "#{args.join(' ')} must exit 0, got: #{output}")
  assert_includes(output, "Usage:\n  shoryuken #{args.include?('check') ? 'check' : 'start'}\n")
  [
    '-c, --concurrency=N', '-q, --queues=one two three', '-r, --require=REQUIRE', '-t, --timeout=N',
    '-C, --config=CONFIG', '    --config-file=CONFIG_FILE', '-R, --[no-]rails', '-L, --logfile=LOGFILE',
    '-v, --[no-]verbose', '-d, --[no-]daemon', '-P, --pidfile=PIDFILE', '-D, --delay=N'
  ].each { |switch| assert_includes(output, switch) }
end

[%w[help sqs], %w[sqs], %w[sqs -h], %w[sqs help], %w[sqs --], %w[sqs -e]].each do |args|
  status, output = run_shoryuken_command_until_exit(*args)
  assert_equal(0, status.exitstatus, "#{args.join(' ')} must exit 0, got: #{output}")
  %w[create delete dump help ls mv purge requeue].each do |command|
    assert(output.match?(/^  shoryuken sqs #{command}\b.*# /), "#{args.join(' ')} must list #{command}, got: #{output}")
  end
  assert_includes(output, '-e, --endpoint=ENDPOINT')
end

[%w[sqs help dump], %w[sqs dump -h], %w[help sqs dump]].each do |args|
  status, output = run_shoryuken_command_until_exit(*args)
  assert_equal(0, status.exitstatus, "#{args.join(' ')} must exit 0, got: #{output}")
  assert_includes(output, "Usage:\n  shoryuken sqs dump QUEUE-NAME\n")
  assert_includes(output, "-d, --[no-]delete        # delete from the queue\n                           # Default: true")
end

# --- version ---
[%w[version], %w[ver]].each do |args|
  status, output = run_shoryuken_command_until_exit(*args)
  assert_equal([0, "Shoryuken #{Shoryuken::VERSION}\n"], [status.exitstatus, output])
end
