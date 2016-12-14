require 'shoryuken/processor'
require 'shoryuken/fetcher'

module Shoryuken
  class Manager
    include Celluloid
    include Util

    attr_accessor :fetcher
    attr_accessor :polling_strategy

    exclusive :dispatch

    trap_exit :processor_died

    BATCH_LIMIT = 10

    def initialize(condvar)
      @count = Shoryuken.options[:concurrency] || 25
      raise(ArgumentError, "Concurrency value #{@count} is invalid, it needs to be a positive number") unless @count > 0
      @queues = Shoryuken.queues.dup.uniq
      @finished = condvar

      @done = false

      @busy_processors  = []
      @busy_threads = {}
      @ready_processors = @count.times.map { build_processor }
    end

    def start
      logger.info { 'Starting' }

      dispatch
    end

    def stop(options = {})
      watchdog('Manager#stop died') do
        @done = true

        if (callback = Shoryuken.stop_callback)
          logger.info { 'Calling Shoryuken.on_stop block' }
          callback.call
        end

        fire_event(:shutdown, true)

        logger.info { "Shutting down #{@ready_processors.size} quiet workers" }

        @ready_processors.each do |processor|
          processor.terminate if processor.alive?
        end
        @ready_processors.clear

        return after(0) { @finished.signal } if @busy_processors.empty?

        if options[:shutdown]
          hard_shutdown_in(options[:timeout])
        else
          soft_shutdown(options[:timeout])
        end
      end
    end

    def processor_done(queue, processor)
      watchdog('Manager#processor_done died') do
        logger.debug { "Process done for '#{queue}'" }

        @busy_processors.delete(processor)
        @busy_threads.delete(processor.object_id)

        if stopped?
          processor.terminate if processor.alive?
          return after(0) { @finished.signal } if @busy_processors.empty?
        else
          @ready_processors << processor
          async.dispatch
        end
      end
    end

    def processor_died(processor, reason)
      watchdog("Manager#processor_died died") do
        logger.error { "Process died, reason: #{reason}" }

        @busy_processors.delete(processor)
        @busy_threads.delete(processor.object_id)

        if stopped?
          return after(0) { @finished.signal } if @busy_processors.empty?
        else
          @ready_processors << build_processor
          async.dispatch
        end
      end
    end

    def stopped?
      @done
    end

    def dispatch
      return if stopped?

      logger.debug { "Ready: #{@ready_processors.size}, Busy: #{@busy_processors.size}, Active Queues: #{polling_strategy.active_queues}" }

      if @ready_processors.empty?
        logger.debug { 'Pausing fetcher, because all processors are busy' }
        dispatch_later
        return
      end

      queue = polling_strategy.next_queue
      if queue.nil?
        logger.debug { 'Pausing fetcher, because all queues are paused' }
        dispatch_later
        return
      end

      batched_queue?(queue) ? dispatch_batch(queue) : dispatch_single_messages(queue)

      async.dispatch
    end

    private

    def dispatch_later
      @_dispatch_timer ||= after(1) do
        @_dispatch_timer = nil
        dispatch
      end
    end

    def assign(queue, sqs_msg)
      watchdog('Manager#assign died') do
        logger.debug { "Assigning #{sqs_msg.message_id}" }

        processor = @ready_processors.pop
        @busy_threads[processor.object_id] = processor.running_thread
        @busy_processors << processor

        processor.async.process(queue, sqs_msg)
      end
    end

    def dispatch_batch(queue)
      batch = fetcher.fetch(queue, BATCH_LIMIT)
      polling_strategy.messages_found(queue.name, batch.size)
      assign(queue.name, patch_batch!(batch))
    end

    def dispatch_single_messages(queue)
      messages = fetcher.fetch(queue, @ready_processors.size)
      polling_strategy.messages_found(queue.name, messages.size)
      messages.each { |message| assign(queue.name, message) }
    end

    def batched_queue?(queue)
      Shoryuken.worker_registry.batch_receive_messages?(queue.name)
    end

    def delay
      Shoryuken.options[:delay].to_f
    end

    def build_processor
      processor = Processor.new_link(current_actor)
      processor.proxy_id = processor.object_id
      processor
    end

    def soft_shutdown(delay)
      logger.info { "Waiting for #{@busy_processors.size} busy workers" }

      if @busy_processors.size > 0
        after(delay) { soft_shutdown(delay) }
      else
        @finished.signal
      end
    end

    def hard_shutdown_in(delay)
      logger.info { "Waiting for #{@busy_processors.size} busy workers" }
      logger.info { "Pausing up to #{delay} seconds to allow workers to finish..." }

      after(delay) do
        watchdog('Manager#hard_shutdown_in died') do
          if @busy_processors.size > 0
            logger.info { "Hard shutting down #{@busy_processors.size} busy workers" }

            @busy_processors.each do |processor|
              if processor.alive? && t = @busy_threads.delete(processor.object_id)
                t.raise Shutdown
              end
            end
          end

          @finished.signal
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
