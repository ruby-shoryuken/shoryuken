class EndlessUninterruptiveWorker
  include Shoryuken::Worker

  # Usage:
  # QUEUE="super-q"
  # MAX_EXECUTION_TIME=2000 QUEUE=$QUEUE \
  # bundle exec ./bin/shoryuken -r ./examples/endless_interruptive_worker.rb -q $QUEUE -c 8

  class << self
    def queue
      ENV['QUEUE'] || 'default'
    end

    def max_execution_time
      ENV["MAX_EXECUTION_TIME"] ? ENV["MAX_EXECUTION_TIME"].to_i : 100
    end

    def rng
      @rng ||= Random.new
    end

    # returns a random number between 0 and 100
    def random_number(hi = 1000)
      (rng.rand * hi).to_i
    end
  end

  def perform(sqs_msg, body)
    Shoryuken.logger.info("Received message: '#{body}'")

    execution_ms = self.class.random_number(self.class.max_execution_time)
    Shoryuken.logger.info("Going to burn metal for #{execution_ms}ms")
    end_time = Time.now + execution_ms.to_f / 1000
    while Time.now < end_time do
      # burn metal
    end

    new_body = "#{execution_ms}-" + body.to_s

    self.class.perform_async(new_body.slice(0, 512))
  end

  shoryuken_options queue: queue, auto_delete: true
end
