module Shoryuken
  class Manager
    include Util

    BATCH_LIMIT = 10

    def initialize(fetcher, polling_strategy)
      @count = Shoryuken.options[:concurrency] || 25
      raise(ArgumentError, "Concurrency value #{@count} is invalid, it needs to be a positive number") unless @count > 0

      @queues = Shoryuken.queues.dup.uniq

      @done = Concurrent::AtomicBoolean.new(false)

      @fetcher = fetcher
      @polling_strategy = polling_strategy

      @ready = Concurrent::AtomicFixnum.new(@count)

      @pool = Concurrent::FixedThreadPool.new(@count)
    end

    def start
      logger.info { 'Starting' }

      dispatch
    end

    def stop(options = {})
      watchdog('Manager#stop died') do
        @done.make_true

        if (callback = Shoryuken.stop_callback)
          logger.info { 'Calling Shoryuken.on_stop block' }
          callback.call
        end

        fire_event(:shutdown, true)

        logger.info { "Shutting down workers" }

        if options[:shutdown]
          hard_shutdown_in(options[:timeout])
        else
          soft_shutdown
        end
      end
    end

    def processor_done(queue)
      watchdog('Manager#processor_done died') do
        logger.debug { "Process done for '#{queue}'" }

        @ready.increment

        dispatch_later unless @done.true?
      end
    end

    def dispatch
      return if @done.true?

      logger.debug { "Ready: #{@ready.value}, Busy: #{busy}, Active Queues: #{@polling_strategy.active_queues}" }

      if @ready.value == 0
        logger.debug { 'Pausing fetcher, because all processors are busy' }
        dispatch_later
        return
      end

      unless queue = @polling_strategy.next_queue
        logger.debug { 'Pausing fetcher, because all queues are paused' }
        dispatch_later
        return
      end

      batched_queue?(queue) ? dispatch_batch(queue) : dispatch_single_messages(queue)

      dispatch_later
    end

    private

    def busy
      @count - @ready.value
    end

    def dispatch_later
      @_dispatch_timer ||= after(1) do
        @_dispatch_timer = nil
        dispatch
      end
    end

    def assign(queue, sqs_msg)
      watchdog('Manager#assign died') do
        logger.debug { "Assigning #{sqs_msg.message_id}" }

        @ready.decrement

        @pool.post { Processor.new(self).process(queue, sqs_msg) }
      end
    end

    def dispatch_batch(queue)
      batch = @fetcher.fetch(queue, BATCH_LIMIT)
      @polling_strategy.messages_found(queue.name, batch.size)
      assign(queue.name, patch_batch!(batch))
    end

    def dispatch_single_messages(queue)
      messages = @fetcher.fetch(queue, @ready.value)
      @polling_strategy.messages_found(queue.name, messages.size)
      messages.each { |message| assign(queue.name, message) }
    end

    def batched_queue?(queue)
      Shoryuken.worker_registry.batch_receive_messages?(queue.name)
    end

    def soft_shutdown
      logger.info { "Waiting for #{busy} busy workers" }

      @pool.shutdown
      @pool.wait_for_termination
    end

    def hard_shutdown_in(delay)
      logger.info { "Waiting for #{busy} busy workers" }

      if busy > 0
        logger.info { "Pausing up to #{delay} seconds to allow workers to finish..." }
        sleep(delay)
      end

      watchdog('Manager#hard_shutdown_in died') do
        if busy > 0
          logger.info { "Hard shutting down #{busy} busy workers" }

          @pool.kill
        end
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
