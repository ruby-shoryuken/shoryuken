require 'yaml'
require 'aws-sdk'
require 'celluloid'

require 'shoryuken/version'
require 'shoryuken/manager'
require 'shoryuken/processor'
require 'shoryuken/fetcher'

module Shoryuken
  class Manager
    include Celluloid
    include Util

    attr_accessor :fetcher

    trap_exit :processor_died

    def initialize
      @count  = Shoryuken.options[:concurrency] || 25
      @queues = Shoryuken.queues.dup.uniq

      @done = false

      @busy  = []
      @ready = @count.times.map { Processor.new_link(current_actor) }
    end

    def start
      logger.info 'Starting'

      dispatch
    end

    def stop(options = {})
      watchdog('Manager#stop died') do
        shutdown = options[:shutdown]
        timeout  = options[:timeout]

        @done = true

        @fetcher.terminate if @fetcher.alive?

        logger.info { "Shutting down #{@ready.size} quiet workers" }

        @ready.each do |processor|
          processor.terminate if processor.alive?
        end
        @ready.clear

        return after(0) { signal(:shutdown) } if @busy.empty?

        hard_shutdown_in(timeout) if shutdown
      end
    end

    def processor_done(queue, processor)
      watchdog('Manager#processor_done died') do
        logger.info "Process done for queue '#{queue}'"

        @busy.delete processor

        if stopped?
          processor.terminate if processor.alive?
        else
          @ready << processor
        end
      end
    end

    def processor_died(processor, reason)
      watchdog("Manager#processor_died died") do
        logger.info "Process died, reason: #{reason}"

        @busy.delete processor

        unless stopped?
          @ready << Processor.new_link(current_actor)
        end
      end
    end

    def stopped?
      @done
    end

    def assign(queue, sqs_msg)
      watchdog("Manager#assign died") do
        logger.info "Assigning #{sqs_msg.id}"

        processor = @ready.pop
        @busy << processor

        processor.async.process(queue, sqs_msg)
      end
    end

    def rebalance_queue_weight!(queue)
      watchdog('Manager#rebalance_queue_weight! died') do
        if (original = original_queue_weight(queue)) > (current = current_queue_weight(queue))
          if current + 1 > original
            logger.info "Increasing queue '#{queue}' weight to #{current + 1}, original: #{original}"
          else
            logger.info "Queue '#{queue}' is back to its normal weight #{original}"
          end

          @queues << queue
        end
      end
    end

    def pause_queue!(queue)
      return unless @queues.include? queue

      logger.info "Pausing queue '#{queue}' for #{Shoryuken.options[:delay].to_f} seconds, because the queue is empty"

      @queues.delete(queue)

      after(Shoryuken.options[:delay].to_f) { async.restart_queue!(queue) }
    end


    def dispatch
      return if stopped?

      logger.debug { "Ready size: #{@ready.size}" }
      logger.debug { "Busy size: #{@busy.size}" }
      logger.debug { "Queues: #{@queues.inspect}" }

      if @ready.empty?
        logger.debug { 'Pausing fetcher, because all processors are busy' }

        after(1) { dispatch }

        return
      end

      if queue = next_queue
        @fetcher.async.fetch(queue, @ready.size)
      else
        logger.debug { 'Pausing fetcher, because all queues are paused' }

        @fetcher_paused = true
      end
    end

    private

    def restart_queue!(queue)
      unless @queues.include? queue
        logger.info "Restarting queue '#{queue}'"

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

      queue = @queues.shift
      @queues << queue

      queue
    end

    def hard_shutdown_in(delay)
      logger.info { "Pausing up to #{delay} seconds to allow workers to finish..." }
      logger.info { "Waiting for #{@busy.size} busy workers" }

      after(delay) do
        watchdog("Manager#hard_shutdown_in died") do
          # We've reached the timeout and we still have busy workers.
          # They must die but their messages shall live on.
          logger.info { "Still waiting for #{@busy.size} busy workers" }

          @busy.each do |processor|
            t = processor.bare_object.actual_work_thread
            t.raise Shutdown if processor.alive?
          end

          after(0) { signal(:shutdown) }
        end
      end
    end
  end
end
