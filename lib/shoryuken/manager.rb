module Shoryuken
  class Manager
    include Util

    BATCH_LIMIT = 10

    def initialize(count, fetcher, polling_strategy)
      @count = count

      @queues = Shoryuken.queues.dup.uniq

      @done = Concurrent::AtomicBoolean.new(false)
      @dispatching = Concurrent::AtomicBoolean.new(false)

      @fetcher = fetcher
      @polling_strategy = polling_strategy

      @heartbeat = Concurrent::TimerTask.new(run_now: true, execution_interval: 0.1, timeout_interval: 60) { dispatch }

      @pool = Concurrent::FixedThreadPool.new(@count, max_queue: @count)
    end

    def start
      logger.info { 'Starting' }

      @heartbeat.execute
    end

    def stop(options = {})
      @done.make_true

      if (callback = Shoryuken.stop_callback)
        logger.info { 'Calling Shoryuken.on_stop block' }
        callback.call
      end

      fire_event(:shutdown, true)

      logger.info { "Shutting down workers" }

      @heartbeat.kill

      if options[:shutdown]
        hard_shutdown_in(options[:timeout])
      else
        soft_shutdown
      end
    end

    def processor_done(queue)
      logger.debug { "Process done for '#{queue}'" }
    end

    private

    def dispatch
      return if @done.true?
      return unless @dispatching.make_true

      logger.debug { "Ready: #{ready}, Busy: #{busy}, Active Queues: #{@polling_strategy.active_queues}" }

      if ready == 0
        return logger.debug { 'Pausing fetcher, because all processors are busy' }
      end

      unless queue = @polling_strategy.next_queue
        return logger.debug { 'Pausing fetcher, because all queues are paused' }
      end

      batched_queue?(queue) ? dispatch_batch(queue) : dispatch_single_messages(queue)
    ensure
      @dispatching.make_false
    end

    def busy
      @count - ready
    end

    def ready
      @pool.remaining_capacity
    end

    def assign(queue, sqs_msg)
      logger.debug { "Assigning #{sqs_msg.message_id}" }

      @pool.post { Processor.new(self).process(queue, sqs_msg) }
    end

    def dispatch_batch(queue)
      batch = @fetcher.fetch(queue, BATCH_LIMIT)
      @polling_strategy.messages_found(queue.name, batch.size)
      assign(queue.name, patch_batch!(batch))
    end

    def dispatch_single_messages(queue)
      messages = @fetcher.fetch(queue, ready)
      @polling_strategy.messages_found(queue.name, messages.size)
      messages.each { |message| assign(queue.name, message) }
    end

    def batched_queue?(queue)
      Shoryuken.worker_registry.batch_receive_messages?(queue.name)
    end

    def soft_shutdown
      @pool.shutdown
      @pool.wait_for_termination
    end

    def hard_shutdown_in(delay)
      if busy > 0
        logger.info { "Pausing up to #{delay} seconds to allow workers to finish..." }
      end

      @pool.shutdown

      unless @pool.wait_for_termination(delay)
        logger.info { "Hard shutting down #{busy} busy workers" }

        @pool.kill
      end
    end

    def patch_batch!(sqs_msgs)
      sqs_msgs.instance_eval do
        def message_id
          "batch-with-#{size}-messages"
        end
      end

      sqs_msgs
    end
  end
end
