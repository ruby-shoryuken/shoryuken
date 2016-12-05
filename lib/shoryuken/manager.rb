require 'shoryuken/processor'
require 'shoryuken/fetcher'

module Shoryuken
  class Manager < Concurrent::Actor::RestartingContext
    include Util

    def initialize
      @count = Shoryuken.options[:concurrency] || 25

      raise(ArgumentError, "Concurrency value #{@count} is invalid, it needs to be a positive number") if @count < 1

      @queues = Shoryuken.queues.dup.uniq

      @done = false

      @busy  = []
      @ready = @count.times.map { build_processor }
      @threads = {}
    end

    def fetcher(fetcher)
      @fetcher = fetcher
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

        @fetcher.ask!(:terminate!)

        logger.info { "Shutting down #{@ready.size} quiet workers" }

        @ready.each do |processor|
          processor.ask!(:terminate!)
        end
        @ready.clear

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
          processor.ask!(:terminate!)
        else
          @ready << processor
        end
      end
    end

    def stopped?
      @done
    end

    def reset
    end

    def terminated(_)
    end

    def assign(queue, sqs_msg)
      watchdog('Manager#assign died') do
        logger.debug { "Assigning #{sqs_msg.message_id}" }

        processor = @ready.pop
        @busy << processor

        processor.tell([:process, queue, sqs_msg])
      end
    end

    def rebalance_queue_weight!(queue)
      watchdog('Manager#rebalance_queue_weight! died') do
        if (original = original_queue_weight(queue)) > (current = current_queue_weight(queue))
          logger.info { "Increasing '#{queue}' weight to #{current + 1}, max: #{original}" }

          @queues << queue
        end
      end
    end

    def pause_queue!(queue)
      return if !@queues.include?(queue) || Shoryuken.options[:delay].to_f <= 0

      logger.debug { "Pausing '#{queue}' for #{Shoryuken.options[:delay].to_f} seconds, because it's empty" }

      @queues.delete(queue)

      after(Shoryuken.options[:delay].to_f) { tell([:restart_queue!, queue]) }
    end


    def dispatch
      return if stopped?

      logger.debug { "Ready: #{@ready.size}, Busy: #{@busy.size}, Active Queues: #{unparse_queues(@queues)}" }

      if @ready.empty?
        logger.debug { 'Pausing fetcher, because all processors are busy' }

        dispatch_later
        return
      end

      if (queue = next_queue)
        @fetcher.tell [:fetch, queue, @ready.size]
      else
        logger.debug { 'Pausing fetcher, because all queues are paused' }

        @fetcher_paused = true
      end
    end

    private

    def dispatch_later
      @_dispatch_timer ||= after(1) do
        @_dispatch_timer = nil
        dispatch
      end
    end

    def build_processor
      Processor.spawn! name: :processor, link: true, args: [self]
    end

    def restart_queue!(queue)
      return if stopped?

      unless @queues.include? queue
        logger.debug { "Restarting '#{queue}'" }

        @queues << queue

        if @fetcher_paused
          logger.debug { 'Restarting fetcher' }

          @fetcher_paused = false

          dispatch
        end
      end
    end

    def current_queue_weight(queue)
      queue_weight(@queues, queue)
    end

    def original_queue_weight(queue)
      queue_weight(Shoryuken.queues, queue)
    end

    def queue_weight(queues, queue)
      queues.count { |q| q == queue }
    end

    def next_queue
      return nil if @queues.empty?

      # get/remove the first queue in the list
      queue = @queues.shift

      unless defined?(::ActiveJob) || !Shoryuken.worker_registry.workers(queue).empty?
        # when no worker registered pause the queue to avoid endless recursion
        logger.debug { "Pausing '#{queue}' for #{Shoryuken.options[:delay].to_f} seconds, because no workers registered" }

        after(Shoryuken.options[:delay].to_f) { tell([:restart_queue!, queue]) }

        return next_queue
      end

      # add queue back to the end of the list
      @queues << queue

      queue
    end

    def soft_shutdown(delay)
      logger.info { "Waiting for #{@busy.size} busy workers" }

      if @busy.size > 0
        after(delay) { soft_shutdown(delay) }
      end
    end

    def hard_shutdown_in(delay)
      logger.info { "Waiting for #{@busy.size} busy workers" }
      logger.info { "Pausing up to #{delay} seconds to allow workers to finish..." }

      # after(delay) do
      #   watchdog('Manager#hard_shutdown_in died') do
      #     if @busy.size > 0
      #       logger.info { "Hard shutting down #{@busy.size} busy workers" }

      #       # @busy.each do |processor|
      #       #   if processor.alive? && t = @threads.delete(processor.object_id)
      #       #     t.raise Shutdown
      #       #   end
      #       # end
      #     end
      #   end
      # end
    end
  end
end
