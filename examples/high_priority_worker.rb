class HighPriorityWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'high_priority', delete: true

  def perform(sqs_msg)
    puts "HighPriorityWorker: '#{sqs_msg.body}'"

    sleep rand(0..1)
  end
end
