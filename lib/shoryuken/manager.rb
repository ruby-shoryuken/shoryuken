module Shoryuken
  class Manager
    include Util

    BATCH_LIMIT = 10

    def initialize(fetcher, polling_strategy)
      @count = Shoryuken.options.fetch(:concurrency, 25)

      raise(ArgumentError, "Concurrency value #{@count} is invalid, it needs to be a positive number") unless @count > 0

      @queues = Shoryuken.queues.dup.uniq

      @done = Concurrent::AtomicBoolean.new(false)

      @fetcher = fetcher
      @polling_strategy = polling_strategy

      @pool = Concurrent::FixedThreadPool.new(@count, max_queue: @count)
      @dispatcher_executor = Concurrent::SingleThreadExecutor.new
    end

    def start
      logger.info { 'Starting' }

      dispatch_async
    end

    def stop(options = {})
      @done.make_true

      if (callback = Shoryuken.stop_callback)
        logger.info { 'Calling Shoryuken.on_stop block' }
        callback.call
      end

      fire_event(:shutdown, true)

      logger.info { 'Shutting down workers' }

      @dispatcher_executor.kill

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

    def dispatch_async
      @dispatcher_executor.post(&method(:dispatch_now))
    end

    def dispatch_now
      return if @done.true?

      begin
        return if ready.zero?
        return unless (queue = @polling_strategy.next_queue)

        logger.debug { "Ready: #{ready}, Busy: #{busy}, Active Queues: #{@polling_strategy.active_queues}" }

        batched_queue?(queue) ? dispatch_batch(queue) : dispatch_single_messages(queue)
      ensure
        dispatch_async
      end
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

      return if @pool.wait_for_termination(delay)

      logger.info { "Hard shutting down #{busy} busy workers" }
      @pool.kill
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
