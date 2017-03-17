module Shoryuken
  class Manager
    include Util

    BATCH_LIMIT        = 10
    HEARTBEAT_INTERVAL = 0.1

    def initialize(fetcher, polling_strategy)
      @count = Shoryuken.options.fetch(:concurrency, 25)

      raise(ArgumentError, "Concurrency value #{@count} is invalid, it needs to be a positive number") unless @count > 0

      @ready = Concurrent::AtomicFixnum.new(@count)

      @queues = Shoryuken.queues.dup.uniq

      @done = Concurrent::AtomicBoolean.new(false)
      @dispatching = Concurrent::AtomicBoolean.new(false)

      @fetcher = fetcher
      @polling_strategy = polling_strategy

      @heartbeat = Concurrent::TimerTask.new(run_now: true,
                                             execution_interval: HEARTBEAT_INTERVAL,
                                             timeout_interval: 60) { dispatch }

      # See https://github.com/ruby-concurrency/concurrent-ruby/blob/master/lib/concurrent/configuration.rb#L167
      @executor = Concurrent::FixedThreadPool.new(@count, auto_terminate: false,
                                                          idletime: 60,
                                                          max_queue: 0,
                                                          fallback_policy: :abort)
      # min_threads = [2, Concurrent.processor_count].max
      # @executor = Concurrent::ThreadPoolExecutor.new(min_threads: min_threads,
      #                                                max_threads: [min_threads, @count].max,
      #                                                auto_terminate: false,
      #                                                idletime: 60,
      #                                                max_queue: 0,
      #                                                fallback_policy: :abort)
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

      logger.info { 'Shutting down workers' }

      @heartbeat.kill

      if options[:shutdown]
        hard_shutdown_in(options[:timeout])
      else
        soft_shutdown
      end
    end

    private

    def on_error(_reason)
      @ready.increment
    end

    def on_success(_result)
      @ready.increment
    end

    def dispatch
      return if @done.true?
      return unless @dispatching.make_true

      while @ready.value.positive?
        return unless (queue = @polling_strategy.next_queue)

        logger.debug { "Ready: #{@ready.value}, Busy: #{busy}, Active Queues: #{@polling_strategy.active_queues}" }

        batched_queue?(queue) ? dispatch_batch(queue) : dispatch_single_messages(queue)
      end
    ensure
      @dispatching.make_false
    end

    def busy
      @count - @ready.value
    end

    def assign(queue, sqs_msg)
      logger.debug { "Assigning #{sqs_msg.message_id}" }

      @ready.decrement

      p = Concurrent::Promise.execute(executor: @executor) { Processor.process(queue, sqs_msg) }
      p.on_success(&method(:on_success)).on_error(&method(:on_error))
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
      @executor.shutdown
      @executor.wait_for_termination
    end

    def hard_shutdown_in(delay)
      if busy > 0
        logger.info { "Pausing up to #{delay} seconds to allow workers to finish..." }
      end

      @executor.shutdown

      return if @executor.wait_for_termination(delay)

      logger.info { "Hard shutting down #{busy} busy workers" }
      @executor.kill
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
