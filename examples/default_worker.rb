class DefaultWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'default', auto_delete: true

  def perform(_sqs_msg, body)
    Shoryuken.logger.debug("Received message: #{body}")
  end
end
