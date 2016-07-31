require 'shoryuken/processor'
require 'shoryuken/fetcher'

module Shoryuken
  class Manager
    include Celluloid
    include Util

    attr_accessor :fetcher
    attr_accessor :polling_strategy

    trap_exit :processor_died

    BATCH_LIMIT = 10

    def initialize(condvar)
      @count = Shoryuken.options[:concurrency] || 25
      raise(ArgumentError, "Concurrency value #{@count} is invalid, it needs to be a positive number") unless @count > 0
      @queues = Shoryuken.queues.dup.uniq
      @finished = condvar

      @done = false

      @busy  = []
      @ready = @count.times.map { build_processor }
      @threads = {}
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

        logger.info { "Shutting down #{@ready.size} quiet workers" }

        @ready.each do |processor|
          processor.terminate if processor.alive?
        end
        @ready.clear

        return after(0) { @finished.signal } if @busy.empty?

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

        @threads.delete(processor.object_id)
        @busy.delete processor

        if stopped?
          processor.terminate if processor.alive?
          return after(0) { @finished.signal } if @busy.empty?
        else
          @ready << processor
        end
      end
    end

    def processor_died(processor, reason)
      watchdog("Manager#processor_died died") do
        logger.error { "Process died, reason: #{reason}" unless reason.to_s.empty? }

        @threads.delete(processor.object_id)
        @busy.delete processor

        if stopped?
          return after(0) { @finished.signal } if @busy.empty?
        else
          @ready << build_processor
        end
      end
    end

    def stopped?
      @done
    end

    def dispatch
      return if stopped?

      logger.debug { "Ready: #{@ready.size}, Busy: #{@busy.size}, Active Queues: #{polling_strategy.active_queues}" }

      if @ready.empty?
        logger.debug { 'Pausing fetcher, because all processors are busy' }
        after(1) { dispatch }
        return
      end

      queue = polling_strategy.next_queue
      if queue == nil 
        logger.debug { 'Pausing fetcher, because all queues are paused' }
        after(1) { dispatch }
        return
      end

      unless defined?(::ActiveJob) || Shoryuken.worker_registry.workers(queue.name).any?
        logger.debug { "Pausing fetcher, because of no registered workers for queue #{queue}" }
        after(1) { dispatch }
        return
      end

      batched_queue?(queue) ? dispatch_batch(queue) : dispatch_single_messages(queue)

      self.async.dispatch
    end

    def real_thread(proxy_id, thr)
      @threads[proxy_id] = thr
    end

    private

    def assign(queue, sqs_msg)
      watchdog('Manager#assign died') do
        logger.debug { "Assigning #{sqs_msg.message_id}" }

        processor = @ready.pop
        @busy << processor

        processor.async.process(queue, sqs_msg)
      end
    end

    def dispatch_batch(queue)
      batch = fetcher.fetch(queue, BATCH_LIMIT)
      self.async.assign(queue.name, patch_batch!(batch))
      polling_strategy.messages_found(queue.name, batch.size)
    end

    def dispatch_single_messages(queue)
      messages = fetcher.fetch(queue, @ready.size)
      messages.each { |message| self.async.assign(queue.name, message) }
      polling_strategy.messages_found(queue.name, messages.size)
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
      logger.info { "Waiting for #{@busy.size} busy workers" }

      if @busy.size > 0
        after(delay) { soft_shutdown(delay) }
      else
        @finished.signal
      end
    end

    def hard_shutdown_in(delay)
      logger.info { "Waiting for #{@busy.size} busy workers" }
      logger.info { "Pausing up to #{delay} seconds to allow workers to finish..." }

      after(delay) do
        watchdog('Manager#hard_shutdown_in died') do
          if @busy.size > 0
            logger.info { "Hard shutting down #{@busy.size} busy workers" }

            @busy.each do |processor|
              if processor.alive? && t = @threads.delete(processor.object_id)
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
