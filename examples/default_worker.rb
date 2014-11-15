class DefaultWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'default', auto_delete: true

  def perform(sqs_msg, body)
    puts "DefaultWorker: '#{body}'"
  end
end

# multiple workers for the same queue
class DefaultWorker2
  include Shoryuken::Worker

  shoryuken_options queue: 'default', auto_delete: true

  def perform(sqs_msg, body)
    puts "DefaultWorker2: '#{body}'"
  end
end
