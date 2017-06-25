module Shoryuken
  class Manager
    include Util

    BATCH_LIMIT = 10
    # See https://github.com/phstc/shoryuken/issues/348#issuecomment-292847028
    MIN_DISPATCH_INTERVAL = 0.1

    def initialize(fetcher, polling_strategy)
      @count = Shoryuken.options.fetch(:concurrency, 25)

      raise(ArgumentError, "Concurrency value #{@count} is invalid, it needs to be a positive number") unless @count > 0

      @done = Concurrent::AtomicBoolean.new(false)

      @fetcher = fetcher
      @polling_strategy = polling_strategy

      @processors = Concurrent::Map.new

      @dispatcher_executor = Concurrent::SingleThreadExecutor.new
    end

    def start
      logger.info { 'Starting' }

      dispatch_async
    end

    def stop(options = {})
      @done.make_true

      if (callback = Shoryuken.stop_callback)
        logger.info { 'Calling on_stop callback' }
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

    def processor_failed(ex)
      logger.error { "Processor failed: #{ex.message}" }
      logger.error { ex.backtrace.join("\n") } unless ex.backtrace.nil?
    end

    def processor_done(queue)
      logger.debug { "Process done for #{queue}" }
    end

    private

    def dispatch_async
      @dispatcher_executor.post(&method(:dispatch_now))
    end

    def dispatch_now
      return if @done.true?

      begin
        if !ready.positive? || (queue = @polling_strategy.next_queue).nil?
          sleep MIN_DISPATCH_INTERVAL
          return
        end

        @processors.put_if_absent(queue.name, Concurrent::Array.new)

        unless ready_for_queue(queue.name).positive?
          sleep MIN_DISPATCH_INTERVAL
          return
        end

        fire_event(:dispatch)

        logger.debug { "Ready: #{ready}, Busy: #{busy}, Active Queues: #{@polling_strategy.active_queues}" }

        batched_queue?(queue) ? dispatch_batch(queue) : dispatch_single_messages(queue)
      ensure
        dispatch_async
      end
    end

    def ready_for_queue(queue_name)
      [
        Shoryuken.queue_concurrency(queue_name) - @processors.get(queue_name).reject(&:complete?).count,
        ready
      ].min
    end

    def busy
      @processors.values.flatten.count(&:rejected?)
    end

    def ready
      @processors.each_key do |key|
        @processors.get(key)&.delete_if(&:complete?)
      end
      @count - @processors.values.flatten.count
    end

    def assign(queue_name, sqs_msg)
      logger.debug { "Assigning #{sqs_msg.message_id}" }

      @processors.get(queue_name) << Concurrent::Future.execute { Processor.new(self).process(queue_name, sqs_msg) }
    end

    def dispatch_batch(queue)
      return if (batch = @fetcher.fetch(queue, BATCH_LIMIT)).none?
      @polling_strategy.messages_found(queue.name, batch.size)
      assign(queue.name, patch_batch!(batch))
    end

    def dispatch_single_messages(queue)
      messages = @fetcher.fetch(queue, ready_for_queue(queue.name))
      @polling_strategy.messages_found(queue.name, messages.size)
      messages.each { |message| assign(queue.name, message) }
    end

    def batched_queue?(queue)
      Shoryuken.worker_registry.batch_receive_messages?(queue.name)
    end

    def soft_shutdown
      Concurrent.global_io_executor.shutdown
      Concurrent.global_io_executor.wait_for_termination
    end

    def hard_shutdown_in(delay)
      if busy > 0
        logger.info { "Pausing up to #{delay} seconds to allow workers to finish..." }
      end

      Concurrent.global_io_executor.shutdown

      return if Concurrent.global_io_executor.wait_for_termination(delay)

      logger.info { "Hard shutting down #{busy} busy workers" }
      Concurrent.global_io_executor.kill
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
