class UppercutWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'uppercut', auto_delete: true

  def perform(sqs_msg)
    puts "Uppercut: '#{sqs_msg.body}'"
  end
end
