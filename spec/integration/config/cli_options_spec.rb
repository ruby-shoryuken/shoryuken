# frozen_string_literal: true

# This spec tests that `shoryuken start` honours its config file and its CLI
# options: `-C` (YAML with ERB and `logfile`), `-q` (queue order and weights),
# `-r` (a directory), `-P` (pidfile) and `-L` (logfile).
#
# Expected behavior: ERB in the config file is evaluated; the config file
# `logfile` gets the log instead of stdout; `-L` gets the log instead of the
# config file `logfile`; `-q` replaces the config file queues and keeps their
# order and weights, so StrictPriority polls the first of two equally weighted
# CLI queues first; `-r` with a directory loads every `.rb` file under it,
# nested ones too; `-P` writes the process pid.
#
# Regression: the `logfile` from the config file was ignored, the log went to
# stdout (#296).
#
# Regression: queues passed with `-q` next to a config file were reordered, so
# StrictPriority polled the first CLI queue last (#552).

setup_sqs

def write_worker(path, name, queue, record)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, <<~RUBY)
    class #{name}
      include Shoryuken::Worker

      shoryuken_options queue: '#{queue}', auto_delete: true

      def perform(sqs_msg, _body)
        File.write('#{record}', sqs_msg.queue_url.split('/').last + "\\n", mode: 'a')
      end
    end
  RUBY
  path
end

def write_config(dir, name, config)
  path = File.join(dir, "#{name}.yml")
  File.write(path, config)
  path
end

def processed(record)
  File.exist?(record) ? File.readlines(record, chomp: true) : []
end

# --- -C: ERB in the config file and its logfile ---
with_queue_and_dir do |queue, dir|
  record = File.join(dir, 'processed')
  logfile = File.join(dir, 'config.log')
  boot_file = write_worker(File.join(dir, 'boot.rb'), 'ConfigFileWorker', queue, record)
  config = write_config(dir, 'erb', <<~YAML)
    logfile: <%= ENV['CLI_OPTIONS_LOGFILE'] %>
    queues:
      - [<%= ENV['CLI_OPTIONS_QUEUE'] %>, 1]
  YAML

  Shoryuken::Client.queues(queue).send_message(message_body: 'erb')

  status, output = run_shoryuken_until(
    '-r', boot_file, '-C', config,
    env: { 'CLI_OPTIONS_LOGFILE' => logfile, 'CLI_OPTIONS_QUEUE' => queue }
  ) { processed(record).any? }

  assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")
  assert_equal([queue], processed(record), 'the queue named through ERB must be processed')
  assert(File.exist?(logfile), "the config file logfile must be written, stdout: #{output}")
  assert_includes(File.read(logfile), 'Starting')
  refute(output.include?('Starting'), "the log must not go to stdout, got: #{output}")
end

# --- -L: the CLI logfile wins over the config file one ---
with_queue_and_dir do |queue, dir|
  record = File.join(dir, 'processed')
  config_logfile = File.join(dir, 'config.log')
  cli_logfile = File.join(dir, 'cli.log')
  boot_file = write_worker(File.join(dir, 'boot.rb'), 'LogfileWorker', queue, record)
  config = write_config(dir, 'logfile', "logfile: #{config_logfile}\n")

  Shoryuken::Client.queues(queue).send_message(message_body: 'logfile')

  status, output = run_shoryuken_until('-r', boot_file, '-C', config, '-q', queue, '-L', cli_logfile) do
    processed(record).any?
  end

  assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")
  assert(File.exist?(cli_logfile), "the -L logfile must be written, stdout: #{output}")
  assert_includes(File.read(cli_logfile), 'Starting')
  refute(File.exist?(config_logfile), 'the config file logfile must not be used')
  refute(output.include?('Starting'), "the log must not go to stdout, got: #{output}")
end

# --- -q: queue order and weights over the config file queues ---
with_queue_and_dir do |high, dir|
  with_queue_and_dir do |low, _|
    record = File.join(dir, 'processed')
    groups = File.join(dir, 'groups')
    boot_file = File.join(dir, 'boot.rb')
    write_worker(File.join(dir, 'high.rb'), 'HighPriorityWorker', high, record)
    write_worker(File.join(dir, 'low.rb'), 'LowPriorityWorker', low, record)
    File.write(boot_file, <<~RUBY)
      require '#{File.join(dir, 'high.rb')}'
      require '#{File.join(dir, 'low.rb')}'

      Shoryuken.on(:startup) do
        File.write('#{groups}', Shoryuken.groups['default'][:queues].join(','))
      end
    RUBY
    config = write_config(dir, 'queues', <<~YAML)
      concurrency: 1
      polling_strategy: StrictPriority
      queues:
        - [#{DT.uuid}, 5]
    YAML

    # StrictPriority ranks queues of equal weight by their order; low is sent first so only that order puts high first
    2.times { |i| Shoryuken::Client.queues(low).send_message(message_body: "low-#{i}") }
    2.times { |i| Shoryuken::Client.queues(high).send_message(message_body: "high-#{i}") }

    status, output = run_shoryuken_until('-r', boot_file, '-C', config, '-q', "#{high},2", "#{low},2") do
      processed(record).size == 4
    end

    assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")
    assert_equal([high, high, low, low].join(','), File.read(groups), 'the CLI queues must keep order and weights')
    assert_equal([high, high, low, low], processed(record), 'the first CLI queue must be polled first')
  end
end

# --- -r: a directory loads every worker file under it ---
with_queue_and_dir do |top_queue, dir|
  with_queue_and_dir do |nested_queue, _|
    record = File.join(dir, 'processed')
    workers = File.join(dir, 'workers')
    write_worker(File.join(workers, 'top_worker.rb'), 'TopLevelWorker', top_queue, record)
    write_worker(File.join(workers, 'nested', 'deep', 'nested_worker.rb'), 'NestedWorker', nested_queue, record)

    Shoryuken::Client.queues(top_queue).send_message(message_body: 'top')
    Shoryuken::Client.queues(nested_queue).send_message(message_body: 'nested')

    status, output = run_shoryuken_until('-r', workers, '-q', top_queue, nested_queue) do
      processed(record).size == 2
    end

    assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")
    assert_equal([nested_queue, top_queue].sort, processed(record).sort, 'workers from every file must be loaded')
    refute(output.include?('No worker supplied'), "no queue may be left without a worker, got: #{output}")
  end
end

# --- -P: the pidfile holds the process pid ---
with_queue_and_dir do |queue, dir|
  record = File.join(dir, 'processed')
  pidfile = File.join(dir, 'shoryuken.pid')
  boot_file = write_worker(File.join(dir, 'boot.rb'), 'PidfileWorker', queue, record)

  Shoryuken::Client.queues(queue).send_message(message_body: 'pidfile')

  pid = nil
  status, output = run_shoryuken_until('-r', boot_file, '-q', queue, '-P', pidfile) do |_log, child|
    pid = child
    processed(record).any?
  end

  assert(status.success?, "the process must exit cleanly, got #{status.inspect}: #{output}")
  assert(File.exist?(pidfile), "the pidfile must be written, got: #{output}")
  assert_equal(pid, File.read(pidfile).to_i, 'the pidfile must hold the process pid')
end
