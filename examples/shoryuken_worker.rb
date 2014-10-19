class ShoryukenWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'shoryuken', delete: true

  def perform(sqs_msg)
    puts "Shoryuken: '#{sqs_msg.body}'"

    sleep rand(0..1)
  end
end
