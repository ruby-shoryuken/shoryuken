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
  def run_shoryuken_until_exit(*args, timeout: 30)
    run_shoryuken_command_until_exit('start', *args, timeout: timeout)
  end

  # Runs `bin/shoryuken sqs` against ElasticMQ until it exits, returns [status, output]
  def run_shoryuken_sqs(*args, timeout: 30)
    run_shoryuken_command_until_exit('sqs', *args, '-e', SHORYUKEN_ENV['AWS_ENDPOINT_URL_SQS'], timeout: timeout)
  end

  # Runs a `bin/shoryuken` command until it exits on its own, returns [status, output]
  def run_shoryuken_command_until_exit(command, *args, timeout: 30)
    Open3.popen2e(SHORYUKEN_ENV, RbConfig.ruby, SHORYUKEN_BIN, command, *args) do |_in, out, wait|
      output = +''
      reader = Thread.new { out.each_line { |line| output << line } }

      unless wait.join(timeout)
        Process.kill('KILL', wait.pid)
        reader.join
        raise IntegrationsHelper::TestFailure, "shoryuken must exit, but it kept running: #{output}"
      end

      reader.join
      [wait.value, output]
    end
  end

  # Runs `bin/shoryuken start` until the block (given the output so far) returns true, stops it with the signal,
  # returns [status, output]
  def run_shoryuken_until(*args, signal: 'TERM', timeout: 30, &condition)
    run_shoryuken_command_until('start', *args, signal: signal, timeout: timeout, &condition)
  end

  # Runs `bin/shoryuken sqs` against ElasticMQ until the block (given the output so far) returns true, stops it with
  # the signal, returns [status, output]
  def run_shoryuken_sqs_until(*args, signal: 'TERM', timeout: 30, &condition)
    run_shoryuken_command_until(
      'sqs', *args, '-e', SHORYUKEN_ENV['AWS_ENDPOINT_URL_SQS'], signal: signal, timeout: timeout, &condition
    )
  end

  # Runs a `bin/shoryuken` command until the block (given the output so far) returns true, stops it with the signal,
  # returns [status, output]
  def run_shoryuken_command_until(command, *args, signal: 'TERM', timeout: 30, &condition)
    Open3.popen2e(SHORYUKEN_ENV, RbConfig.ruby, SHORYUKEN_BIN, command, *args) do |_in, out, wait|
      output = +''
      reader = Thread.new { out.each_line { |line| output << line } }

      begin
        Timeout.timeout(timeout) { sleep 0.1 until condition.call(output) || !wait.alive? }
      rescue Timeout::Error
        Process.kill('KILL', wait.pid)
      end

      unless condition.call(output)
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
end
