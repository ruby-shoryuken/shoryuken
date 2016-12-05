class DefaultWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'test.fifo', auto_delete: true

  def perform(sqs_msg, body)
    Shoryuken.logger.info("Received message: '#{body}'")

    raise body
  end
end

10.times { |i| DefaultWorker.perform_async("#{rand(1000)}-#{i}}") }
