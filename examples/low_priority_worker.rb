class LowPriorityWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'low_priority', delete: true

  def perform(sqs_msg)
    puts "LowPriorityWorker: '#{sqs_msg.body}'"

    sleep rand(0..1)
  end
end
