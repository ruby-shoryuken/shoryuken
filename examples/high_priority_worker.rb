class HighPriorityWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'high_priority', auto_delete: true

  def perform(sqs_msg, body)
    puts "HighPriorityWorker: '#{body}'"
  end
end
