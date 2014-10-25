class DefaultWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'default', delete: true, body_parser: ->(sqs_msg){ "new body: #{sqs_msg.body}" }

  def perform(sqs_msg, body)
    puts "DefaultWorker: '#{body}'"
  end
end
