class DefaultWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'default_queue', delete: true

  def perform(sqs_msg)
    puts "DefaultWorker: '#{sqs_msg.body}'"

    sleep rand(0..1)
  end
end
