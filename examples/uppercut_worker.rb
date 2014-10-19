class UppercutWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'uppercut', delete: true

  def perform(sqs_msg)
    puts "Uppercut: '#{sqs_msg.body}'"

    sleep rand(0..1)
  end
end
