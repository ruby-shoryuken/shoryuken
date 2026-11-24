# frozen_string_literal: true

# Runs bin/shoryuken in a child process with stdout and stderr captured apart
module SplitOutputHelper
  # Runs a `bin/shoryuken` command until it exits on its own, returns [status, stdout, stderr]
  def run_shoryuken_command_until_exit_split(command, *args, timeout: 30, env: {})
    env = ProcessHelper::SHORYUKEN_ENV.merge(env)

    Open3.popen3(env, RbConfig.ruby, ProcessHelper::SHORYUKEN_BIN, command, *args) do |_in, out, err, wait|
      stdout = +''
      stderr = +''
      readers = [
        Thread.new { out.each_line { |line| stdout << line } },
        Thread.new { err.each_line { |line| stderr << line } }
      ]

      unless wait.join(timeout)
        Process.kill('KILL', wait.pid)
        readers.each(&:join)
        raise IntegrationsHelper::TestFailure, "shoryuken must exit, but it kept running: #{stdout}#{stderr}"
      end

      unless readers.all? { |reader| reader.join(timeout) }
        raise IntegrationsHelper::TestFailure, "shoryuken exited, but a process it left kept its output open: #{stdout}"
      end

      [wait.value, stdout, stderr]
    end
  end
end
