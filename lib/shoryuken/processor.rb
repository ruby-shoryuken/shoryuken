module Shoryuken
  class Processor
    include Util

    BATCH_LIMIT = 10

    def initialize(fetcher, polling_strategy)
      @fetcher = fetcher
      @polling_strategy = polling_strategy
      # what is the worst thing that could happen because it's not atomic?
      # is it possible that it evaluates to true even if we never set it to true?
      @done = false
    end

    def start
      # does updating and evaluating @thread has to be wrapped in mutex?
      # can it throw exception?
      # what should we do if it dies?
      @thread ||= spawn_thread(&method(:loop))
    end

    def terminate(wait=false)
      @done = true
      # does updating and evaluating @thread has to be wrapped in mutex?
      return if !@thread
      @thread.value if wait
    end

    def kill
      @done = true
      # does updating and evaluating @thread has to be wrapped in mutex?
      return if !@thread
      @thread.raise ::Shoryuken::Shutdown
    end

    def alive?
      # is this ok?
      !!@thread.status
    end

    private

    def loop
      while !@done
        do_work
      end
    rescue ::Shoryuken::Shutdown
      # killed, bail!
    rescue => e
      # are we safe to retry here? What are kind of errors we do not want to recover from?
      # OOM?
      logger.debug { "Processor caught exception: #{e}" }
      retry
    end

    def do_work
      queue = @polling_strategy.next_queue
      return logger.info { 'Doing nothing, all queues are paused' } if queue.nil?
      batched_queue?(queue) ? dispatch_batch(queue) : dispatch_single_message(queue)
    end

    def dispatch_batch(queue)
      batch = @fetcher.fetch(queue, BATCH_LIMIT)
      @polling_strategy.messages_found(queue.name, batch.size)
      process(queue.name, patch_batch!(batch))
    end

    def dispatch_single_message(queue)
      messages = @fetcher.fetch(queue, 1)
      @polling_strategy.messages_found(queue.name, messages.size)
      process(queue.name, messages.first) if messages.length > 0
    end

    def batched_queue?(queue)
      Shoryuken.worker_registry.batch_receive_messages?(queue.name)
    end

    def process(queue, sqs_msg)
      worker = Shoryuken.worker_registry.fetch_worker(queue, sqs_msg)
      body = get_body(worker.class, sqs_msg)

      worker.class.server_middleware.invoke(worker, queue, sqs_msg, body) do
        worker.perform(sqs_msg, body)
      end
    end
    
    def spawn_thread(&block)
      Thread.new do 
        block.call
      end
    end

    def get_body(worker_class, sqs_msg)
      if sqs_msg.is_a? Array
        sqs_msg.map { |m| parse_body(worker_class, m) }
      else
        parse_body(worker_class, sqs_msg)
      end
    end

    def parse_body(worker_class, sqs_msg)
      body_parser = worker_class.get_shoryuken_options['body_parser']

      case body_parser
      when :json
        JSON.parse(sqs_msg.body)
      when Proc
        body_parser.call(sqs_msg)
      when :text, nil
        sqs_msg.body
      else
        if body_parser.respond_to?(:parse)
          # JSON.parse
          body_parser.parse(sqs_msg.body)
        elsif body_parser.respond_to?(:load)
          # see https://github.com/phstc/shoryuken/pull/91
          # JSON.load
          body_parser.load(sqs_msg.body)
        end
      end
    rescue => e
      logger.error { "Error parsing the message body: #{e.message}\nbody_parser: #{body_parser}\nsqs_msg.body: #{sqs_msg.body}" }
      raise
    end
  end
end
