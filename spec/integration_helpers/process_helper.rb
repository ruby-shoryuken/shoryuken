# frozen_string_literal: true

# Helpers for specs that run bin/shoryuken in a child process
module ProcessHelper
  SHORYUKEN_BIN = File.expand_path('../../bin/shoryuken', __dir__)

  SHORYUKEN_ENV = {
    'AWS_ENDPOINT_URL_SQS' => 'http://localhost:9324',
    'AWS_REGION' => 'us-east-1',
    'AWS_ACCESS_KEY_ID' => 'fake',
    'AWS_SECRET_ACCESS_KEY' => 'fake'
  }.freeze

  # Runs `bin/shoryuken start` until it exits on its own, returns [status, output]
  def run_shoryuken_until_exit(*args, **options)
    run_shoryuken_command_until_exit('start', *args, **options)
  end

  # Runs `bin/shoryuken sqs` against ElasticMQ until it exits, returns [status, output]
  def run_shoryuken_sqs(*args, **options)
    run_shoryuken_command_until_exit('sqs', *args, '-e', SHORYUKEN_ENV['AWS_ENDPOINT_URL_SQS'], **options)
  end

  # Runs a `bin/shoryuken` command (or another shoryuken executable, with extra env) until it exits on its own,
  # returns [status, output]
  def run_shoryuken_command_until_exit(command, *args, timeout: 30, bin: SHORYUKEN_BIN, env: {})
    Open3.popen2e(SHORYUKEN_ENV.merge(env), RbConfig.ruby, bin, command, *args) do |_in, out, wait|
      output = +''
      reader = Thread.new { out.each_line { |line| output << line } }

      unless wait.join(timeout)
        Process.kill('KILL', wait.pid)
        reader.join
        raise IntegrationsHelper::TestFailure, "shoryuken must exit, but it kept running: #{output}"
      end

      unless reader.join(timeout)
        raise IntegrationsHelper::TestFailure, "shoryuken exited, but a process it left kept its output open: #{output}"
      end

      [wait.value, output]
    end
  end

  # Runs `bin/shoryuken start` until the block (given the output so far and the pid) returns true, stops it with the
  # signal, returns [status, output]
  def run_shoryuken_until(*args, **options, &condition)
    run_shoryuken_command_until('start', *args, **options, &condition)
  end

  # Runs `bin/shoryuken sqs` against ElasticMQ until the block (given the output so far) returns true, stops it with
  # the signal, returns [status, output]
  def run_shoryuken_sqs_until(*args, **options, &condition)
    run_shoryuken_command_until('sqs', *args, '-e', SHORYUKEN_ENV['AWS_ENDPOINT_URL_SQS'], **options, &condition)
  end

  # Runs a `bin/shoryuken` command (or another shoryuken executable, with extra env, in another directory) until the
  # block (given the output so far and the pid) returns true, stops it with the signal, returns [status, output]
  def run_shoryuken_command_until(
    command, *args, signal: 'TERM', timeout: 30, bin: SHORYUKEN_BIN, env: {}, chdir: Dir.pwd, &condition
  )
    Open3.popen2e(SHORYUKEN_ENV.merge(env), RbConfig.ruby, bin, command, *args, chdir: chdir) do |_in, out, wait|
      output = +''
      reader = Thread.new { out.each_line { |line| output << line } }

      begin
        Timeout.timeout(timeout) { sleep 0.1 until condition.call(output, wait.pid) || !wait.alive? }
      rescue Timeout::Error
        Process.kill('KILL', wait.pid)
      end

      unless condition.call(output, wait.pid)
        reader.join
        raise IntegrationsHelper::TestFailure, "shoryuken stopped or timed out before the condition was met: #{output}"
      end

      Process.kill(signal, wait.pid)

      unless wait.join(timeout)
        Process.kill('KILL', wait.pid)
        reader.join
        raise IntegrationsHelper::TestFailure, "shoryuken must exit after #{signal}, but it kept running: #{output}"
      end

      reader.join
      [wait.value, output]
    end
  end

  # Runs `bin/shoryuken start -d` with the pidfile and logfile until the launching process exits, waits for the pidfile,
  # yields [launcher status, launcher output, daemon pid] and kills the daemon if it still runs afterwards
  def with_shoryuken_daemon(pidfile, logfile, *args, timeout: 30)
    status, output = run_shoryuken_until_exit('-d', '-P', pidfile, '-L', logfile, *args, timeout: timeout)

    begin
      Timeout.timeout(timeout) { sleep 0.1 until File.exist?(pidfile) && File.read(pidfile).end_with?("\n") }
    rescue Timeout::Error
      log = File.exist?(logfile) ? File.read(logfile) : ''
      raise IntegrationsHelper::TestFailure, "the daemon must write the pidfile, output: #{output}, log: #{log}"
    end

    yield status, output, File.read(pidfile).to_i
  ensure
    pid = File.exist?(pidfile) ? File.read(pidfile).to_i : 0
    Process.kill('KILL', pid) if pid.positive? && process_alive?(pid)
  end

  # Sends the signal to a process this one did not spawn and waits for it to exit, killing it after the timeout,
  # returns whether it exited on the signal
  def stop_process(pid, signal: 'TERM', timeout: 30)
    Process.kill(signal, pid)
    Timeout.timeout(timeout) { sleep 0.1 while process_alive?(pid) }
    true
  rescue Errno::ESRCH
    false
  rescue Timeout::Error
    Process.kill('KILL', pid)
    false
  end

  # Returns whether a process with the pid runs
  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end
end
