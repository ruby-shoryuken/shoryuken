# frozen_string_literal: true

module Shoryuken
  # Manages message dispatching and processing for a single processing group.
  # Coordinates between the fetcher, polling strategy, and processor.
  class Manager
    include Util

    # Maximum number of messages to fetch in a single batch request
    BATCH_LIMIT = 10

    # Minimum interval between dispatch cycles
    # @see https://github.com/ruby-shoryuken/shoryuken/issues/348#issuecomment-292847028
    MIN_DISPATCH_INTERVAL = 0.1

    # @return [String] the processing group name
    attr_reader :group

    # Initializes a new Manager for a processing group
    #
    # @param group [String] the processing group name
    # @param fetcher [Shoryuken::Fetcher] the message fetcher
    # @param polling_strategy [Shoryuken::Polling::BaseStrategy] the polling strategy
    # @param concurrency [Integer] the maximum number of concurrent processors
    # @param executor [Concurrent::ExecutorService] the executor for async operations
    def initialize(group, fetcher, polling_strategy, concurrency, executor)
      @group                      = group
      @fetcher                    = fetcher
      @polling_strategy           = polling_strategy
      @max_processors             = concurrency
      @busy_processors            = Shoryuken::Helpers::AtomicCounter.new(0)
      @executor                   = executor
      @running                    = Shoryuken::Helpers::AtomicBoolean.new(true)
      @stop_new_dispatching       = Shoryuken::Helpers::AtomicBoolean.new(false)
      @dispatching_release_signal = ::Queue.new
    end

    # Starts the dispatch loop
    #
    # @return [void]
    def start
      fire_utilization_update_event
      dispatch_loop
    end

    # Signals the manager to stop dispatching new messages
    #
    # @return [void]
    def stop_new_dispatching
      @stop_new_dispatching.make_true
    end

    # Waits for any in-progress dispatching to complete
    #
    # @return [void]
    def await_dispatching_in_progress
      # There might still be a dispatching on-going, as the response from SQS could take some time
      # We don't want to stop the process before processing incoming messages, as they would stay "in-flight" for some time on SQS
      # We use a queue, as the dispatch_loop is running on another thread, and this is a efficient way of communicating between threads.
      @dispatching_release_signal.pop
    end

    # Checks if the manager is still running
    #
    # @return [Boolean] true if the manager is running
    def running?
      @running.true? && @executor.running?
    end

    private

    # The main dispatch loop
    #
    # @return [void]
    def dispatch_loop
      if @stop_new_dispatching.true? || !running?
        @dispatching_release_signal << 1
        return
      end

      @executor.post { dispatch }
    end

    # Dispatches messages from a queue
    #
    # @return [void]
    def dispatch
      return unless running?

      if ready <= 0 || (queue = @polling_strategy.next_queue).nil?
        return sleep(MIN_DISPATCH_INTERVAL)
      end

      fire_event(:dispatch, false, queue_name: queue.name)

      Shoryuken.monitor.publish('manager.dispatch',
                                group: @group,
                                queue: queue.name,
                                ready: ready,
                                busy: busy,
                                active_queues: @polling_strategy.active_queues)

      batched_queue?(queue) ? dispatch_batch(queue) : dispatch_single_messages(queue)
    rescue => e
      handle_dispatch_error(e)
    ensure
      dispatch_loop
    end

    # Returns the count of busy processors
    #
    # @return [Integer] the number of busy processors
    def busy
      @busy_processors.value
    end

    # Returns the count of ready processors
    #
    # @return [Integer] the number of available processors
    def ready
      @max_processors - busy
    end

    # Handles completion of processor work
    #
    # @param queue [String] the queue name
    # @return [void]
    def processor_done(queue)
      @busy_processors.decrement
      fire_utilization_update_event

      client_queue = Shoryuken::Client.queues(queue)
      return unless client_queue.fifo?
      return unless @polling_strategy.respond_to?(:message_processed)

      @polling_strategy.message_processed(queue)
    end

    # Assigns a message to a processor
    #
    # @param queue_name [String] the queue name
    # @param sqs_msg [Aws::SQS::Types::Message, Array<Aws::SQS::Types::Message>] the message or batch
    # @return [Concurrent::Promise, nil] the processing promise or nil if not running
    def assign(queue_name, sqs_msg)
      return unless running?

      message_id = sqs_msg.respond_to?(:message_id) ? sqs_msg.message_id : sqs_msg.to_s
      Shoryuken.monitor.publish('manager.processor_assigned',
                                group: @group,
                                queue: queue_name,
                                message_id: message_id)

      @busy_processors.increment
      fire_utilization_update_event

      Concurrent::Promise
        .execute(executor: @executor) do
          original_priority = Thread.current.priority
          begin
            Thread.current.priority = Shoryuken.thread_priority
            Processor.process(queue_name, sqs_msg)
          ensure
            Thread.current.priority = original_priority
          end
        end
        .then { processor_done(queue_name) }
        .rescue { processor_done(queue_name) }
    end

    # Dispatches a batch of messages from a queue
    #
    # @param queue [Shoryuken::Polling::QueueConfiguration] the queue configuration
    # @return [void]
    def dispatch_batch(queue)
      batch = @fetcher.fetch(queue, BATCH_LIMIT)
      @polling_strategy.messages_found(queue.name, batch.size)
      assign(queue.name, patch_batch!(batch)) if batch.any?
    end

    # Dispatches individual messages from a queue
    #
    # @param queue [Shoryuken::Polling::QueueConfiguration] the queue configuration
    # @return [void]
    def dispatch_single_messages(queue)
      messages = @fetcher.fetch(queue, ready)
      @polling_strategy.messages_found(queue.name, messages.size)
      messages.each { |message| assign(queue.name, message) }
    end

    # Checks if a queue uses batch message processing
    #
    # @param queue [Shoryuken::Polling::QueueConfiguration] the queue configuration
    # @return [Boolean] true if the queue is configured for batch processing
    def batched_queue?(queue)
      Shoryuken.worker_registry.batch_receive_messages?(queue.name)
    end

    # Patches a batch array with a message_id method
    #
    # @param sqs_msgs [Array<Aws::SQS::Types::Message>] the batch of messages
    # @return [Array<Aws::SQS::Types::Message>] the patched batch
    def patch_batch!(sqs_msgs)
      sqs_msgs.instance_eval do
        def message_id
          "batch-with-#{size}-messages"
        end
      end

      sqs_msgs
    end

    # Handles errors during dispatch
    #
    # @param ex [Exception] the exception that occurred
    # @return [void]
    def handle_dispatch_error(ex)
      Shoryuken.monitor.publish('manager.failed',
                                group: @group,
                                error: ex,
                                error_message: ex.message,
                                error_class: ex.class.name,
                                backtrace: ex.backtrace)

      Process.kill('USR1', Process.pid)

      @running.make_false
    end

    # Fires a utilization update event
    #
    # @return [void]
    def fire_utilization_update_event
      fire_event :utilization_update, false, {
        group: @group,
        max_processors: @max_processors,
        busy_processors: busy
      }
    end
  end
end
