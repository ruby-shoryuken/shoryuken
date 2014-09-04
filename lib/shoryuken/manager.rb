require 'yaml'
require 'aws-sdk'
require 'celluloid'
require 'multi_json'

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

    def initialize(config)
      @sqs = AWS::SQS.new

      @count   = config['concurrency'] || 25
      @queues  = config['queues'].map { |name| @sqs.queues.named(name) }

      @done = false

      @busy  = []
      @ready = @count.times.map { Processor.new_link(current_actor) }
    end

    def start
      logger.info 'Starting'

      @ready.each { dispatch }
    end

    def stop
      watchdog('Manager#stop died') do
        logger.info 'Bye'

        @done = true

        @fetcher.terminate if @fetcher.alive?

        @ready.each do |processor|
          processor.terminate if processor.alive?
        end
        @ready.clear

        # return after(0) { signal(:shutdown) } if @busy.empty?

        after(0) { signal(:shutdown) }
      end
    end

    def processor_done(processor)
      watchdog('Manager#processor_done died') do
        logger.info "Process done #{processor}"

        @busy.delete processor

        if stopped?
          processor.terminate if processor.alive?
        else
          @ready << processor
        end

        dispatch
      end
    end

    def processor_died(processor, reason)
      watchdog("Manager#processor_died died") do
        logger.info "Process died, reason: #{reason}"

        @busy.delete processor

        unless stopped?
          @ready << Processor.new_link(current_actor)

          dispatch
        end
      end
    end

    def stopped?
      @done
    end

    def assign(queue, sqs_msg)
      watchdog("Manager#assign died") do
        logger.info "Assigning #{sqs_msg}"

        processor = @ready.pop
        @busy << processor

        payload = MultiJson.decode(sqs_msg.body)

        processor.async.process(queue, sqs_msg, payload)
      end
    end

    def skip_and_dispatch(queue)
      dispatch(@queues - [queue])
    end

    def dispatch(queues = [])
      return if stopped?

      queues = @queues if queues.to_a.empty?

      @fetcher.async.fetch(queues.sample)
    end
  end
end
