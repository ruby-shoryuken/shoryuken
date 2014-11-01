class LowPriorityWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'low_priority', auto_delete: true, batch: true

  def perform(sqs_msgs, bodies)
    bodies.each_with_index do |body, index|
      puts "LowPriorityWorker (#{index}): '#{body}'"
    end
  end
end
