module Shoryuken
  class Manager
    include Util

    BATCH_LIMIT = 10
    # See https://github.com/phstc/shoryuken/issues/348#issuecomment-292847028
    MIN_DISPATCH_INTERVAL = 0.1

    def initialize(fetcher, polling_strategy, concurrency)
      @count = concurrency

      @done = Concurrent::AtomicBoolean.new(false)

      @fetcher = fetcher
      @polling_strategy = polling_strategy

      @processors = Concurrent::Array.new
    end

    def start
      dispatch
    end

    def stop
      @done.make_true
    end

    private

    def dispatch
      return if @done.true?

      @processors.reject!(&:complete?)

      if !ready.positive? || (queue = @polling_strategy.next_queue).nil?
        return dispatch_later
      end

      fire_event(:dispatch)

      logger.debug { "Ready: #{ready}, Busy: #{busy}, Active Queues: #{@polling_strategy.active_queues}" }

      batched_queue?(queue) ? dispatch_batch(queue) : dispatch_single_messages(queue)

      Concurrent::Future.execute(&method(:dispatch))
    end

    def dispatch_later
      Concurrent::Future.execute do
        sleep(MIN_DISPATCH_INTERVAL)
        dispatch
      end
    end

    def busy
      @processors.reject(&:complete?).count
    end

    def ready
      @count - busy
    end

    def assign(queue_name, sqs_msg)
      logger.debug { "Assigning #{sqs_msg.message_id}" }

      @processors << Concurrent::Future.execute { Processor.new.process(queue_name, sqs_msg) }
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
