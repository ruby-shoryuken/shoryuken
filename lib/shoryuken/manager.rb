module Shoryuken
  class Manager
    include Util

    BATCH_LIMIT = 10
    # See https://github.com/phstc/shoryuken/issues/348#issuecomment-292847028
    MIN_DISPATCH_INTERVAL = 0.1

    attr_reader :group

    def initialize(group, fetcher, polling_strategy, concurrency, executor)
      @group                         = group
      @fetcher                       = fetcher
      @polling_strategy              = polling_strategy
      @max_processors                = concurrency
      @busy_processors               = Concurrent::AtomicFixnum.new(0)
      @executor                      = executor
      @running                       = Concurrent::AtomicBoolean.new(true)
      @stop_new_dispatching          = Concurrent::AtomicBoolean.new(false)
      @dispatch_mutex                = Mutex.new
      @dispatch_mutex_release_signal = ::Queue.new
    end

    def start
      fire_utilization_update_event
      dispatch_loop(first_run: true)
    end

    def stop_new_dispatching
      @stop_new_dispatching.make_true
    end

    def await_dispatching_in_progress
      @dispatch_mutex.synchronize {}
    end

    def running?
      @running.true? && @executor.running?
    end

    private

    def dispatch_loop(first_run: false)
      # dispatch_mutex_release_signal is a queue meant to implement a wait between different threads which could run
      # that dispatch_loop method. We want it to be empty for the first occurence of the loop, as no other thread is involved yet.
      @dispatch_mutex_release_signal << 1 if !first_run

      @dispatch_mutex.synchronize {
        return unless running?
        return if @stop_new_dispatching.true?
  
        @executor.post { dispatch }

        # we don't want to release @dispatch_mutex until the next execution of dispatch_loop
        # pop will wait until there's an element inserted by a subsequent dispatch_loop execution in another thread
        @dispatch_mutex_release_signal.pop
      }
    end

    def dispatch
      return unless running?

      if ready <= 0 || (queue = @polling_strategy.next_queue).nil?
        return sleep(MIN_DISPATCH_INTERVAL)
      end

      fire_event(:dispatch, false, queue_name: queue.name)

      logger.debug { "Ready: #{ready}, Busy: #{busy}, Active Queues: #{@polling_strategy.active_queues}" }

      batched_queue?(queue) ? dispatch_batch(queue) : dispatch_single_messages(queue)
    rescue => e
      handle_dispatch_error(e)
    ensure
      dispatch_loop
    end

    def busy
      @busy_processors.value
    end

    def ready
      @max_processors - busy
    end

    def processor_done(queue)
      @busy_processors.decrement
      fire_utilization_update_event

      client_queue = Shoryuken::Client.queues(queue)
      return unless client_queue.fifo?
      return unless @polling_strategy.respond_to?(:message_processed)

      @polling_strategy.message_processed(queue)
    end

    def assign(queue_name, sqs_msg)
      return unless running?

      logger.debug { "Assigning #{sqs_msg.message_id}" }

      @busy_processors.increment
      fire_utilization_update_event

      Concurrent::Promise
        .execute(executor: @executor) { Processor.process(queue_name, sqs_msg) }
        .then { processor_done(queue_name) }
        .rescue { processor_done(queue_name) }
    end

    def dispatch_batch(queue)
      batch = @fetcher.fetch(queue, BATCH_LIMIT)
      @polling_strategy.messages_found(queue.name, batch.size)
      assign(queue.name, patch_batch!(batch)) if batch.any?
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

    def handle_dispatch_error(ex)
      logger.error { "Manager failed: #{ex.message}" }
      logger.error { ex.backtrace.join("\n") } unless ex.backtrace.nil?

      Process.kill('USR1', Process.pid)

      @running.make_false
    end

    def fire_utilization_update_event
      fire_event :utilization_update, false, {
        group: @group,
        max_processors: @max_processors,
        busy_processors: busy
      }
    end
  end
end
