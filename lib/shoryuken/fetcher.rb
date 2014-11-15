module Shoryuken
  class Fetcher
    include Celluloid
    include Util

    FETCH_LIMIT = 10

    def initialize(manager)
      @manager = manager
    end

    def receive_message(queue, limit)
      # AWS limits the batch size by 10
      limit = limit > FETCH_LIMIT ? FETCH_LIMIT : limit

      options = Shoryuken.options[:aws][:receive_message].to_h
      options[:limit] = limit
      options[:message_attribute_names] ||= []
      options[:message_attribute_names] << 'shoryuken_class'

      Shoryuken::Client.receive_message queue, options
    end

    def fetch(queue, available_processors)
      watchdog('Fetcher#fetch died') do
        started_at = Time.now

        logger.debug "Looking for new messages in '#{queue}'"

        begin
          batch = !!(Shoryuken.workers[queue] && Shoryuken.workers[queue].get_shoryuken_options['batch'])

          limit = batch ? FETCH_LIMIT : available_processors

          if (sqs_msgs = Array(receive_message(queue, limit))).any?
            logger.info "Found #{sqs_msgs.size} messages for '#{queue}'"

            if batch
              @manager.async.assign(queue, patch_sqs_msgs!(sqs_msgs))
            else
              sqs_msgs.each { |sqs_msg| @manager.async.assign(queue, sqs_msg) }
            end

            @manager.async.rebalance_queue_weight!(queue)
          else
            logger.debug "No message found for '#{queue}'"

            @manager.async.pause_queue!(queue)
          end

          @manager.async.dispatch

          logger.debug { "Fetcher for '#{queue}' completed in #{elapsed(started_at)} ms" }
        rescue => ex
          logger.error "Error fetching message: #{ex}"
          logger.error ex.backtrace.first

          @manager.async.dispatch
        end
      end

    end
    private

    def patch_sqs_msgs!(sqs_msgs)
      sqs_msgs.instance_eval do
        def id
          "batch-with-#{size}-messages"
        end
      end

      sqs_msgs
    end
  end
end
