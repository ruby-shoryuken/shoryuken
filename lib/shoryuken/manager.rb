module Shoryuken
  class Manager
    include Util

    BATCH_LIMIT = 10
    # See https://github.com/phstc/shoryuken/issues/348#issuecomment-292847028
    MIN_DISPATCH_INTERVAL = 0.1

    def initialize(fetcher, polling_strategy, concurrency, executor)
      @fetcher          = fetcher
      @polling_strategy = polling_strategy
      @max_processors   = concurrency
      @busy_processors  = Concurrent::AtomicFixnum.new(0)
      @executor         = executor
    end

    def start
      dispatch_loop
    end

    private

    def running?
      @executor.running?
    end

    def dispatch_loop
      Concurrent::Promise.execute(executor: @executor) {
        dispatch
      }.then { dispatch_loop if running? }.rescue { |ex| raise ex }
    end

    def dispatch
      return unless running?

      if ready <= 0 || (queue = @polling_strategy.next_queue).nil?
        return sleep(MIN_DISPATCH_INTERVAL)
      end

      fire_event(:dispatch)

      logger.debug { "Ready: #{ready}, Busy: #{busy}, Active Queues: #{@polling_strategy.active_queues}" }

      batched_queue?(queue) ? dispatch_batch(queue) : dispatch_single_messages(queue)
    end

    def busy
      @busy_processors.value
    end

    def ready
      @max_processors - busy
    end

    def processor_done
      @busy_processors.decrement
    end

    def assign(queue_name, sqs_msg)
      return if running?

      logger.debug { "Assigning #{sqs_msg.message_id}" }

      @busy_processors.increment

      Concurrent::Promise.execute(executor: @executor) {
        Processor.new(queue_name, sqs_msg).process
      }.then { processor_done }.rescue { processor_done }
    end

    def dispatch_batch(queue)
      return if (batch = @fetcher.fetch(queue, BATCH_LIMIT)).none?
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
