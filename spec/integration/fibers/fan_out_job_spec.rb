# frozen_string_literal: true

# This spec tests a job that runs its work in concurrent Async tasks. The tasks
# overlap, the job finishes with all their results, its message is deleted and
# the thread is left without a Fiber scheduler.

require 'async'

setup_sqs

log = StringIO.new
Shoryuken.logger = Logger.new(log)

with_queue_and_dir do |queue, _dir|
  Shoryuken.add_group('default', 2)
  Shoryuken.add_queue(queue, 1, 'default')

  worker = Class.new do
    include Shoryuken::Worker

    shoryuken_options auto_delete: true

    def perform(_sqs_msg, body)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      results = Sync do |task|
        tasks = Array.new(5) do |i|
          task.async do
            sleep(0.2)
            "#{body}-#{i}"
          end
        end

        tasks.map(&:wait)
      end

      DT[:jobs] << {
        results: results,
        elapsed: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
        scheduler: Fiber.scheduler
      }
    end
  end

  worker.get_shoryuken_options['queue'] = queue
  Shoryuken.register_worker(queue, worker)

  worker.perform_async('a')
  worker.perform_async('b')

  poll_queues_until(timeout: 20) { DT[:jobs].size >= 2 }

  assert_equal(
    [%w[a-0 a-1 a-2 a-3 a-4], %w[b-0 b-1 b-2 b-3 b-4]],
    DT[:jobs].map { |job| job[:results] }.sort
  )
  DT[:jobs].each do |job|
    assert(job[:elapsed] < 0.9, "the tasks must overlap, took #{job[:elapsed]}s")
    assert_equal(nil, job[:scheduler])
  end
  refute(log.string.include?('left a Fiber scheduler set'), log.string)
  assert_equal(0, queue_size(queue))
end
