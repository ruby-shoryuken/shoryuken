class ShoryukenWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'shoryuken', auto_delete: true

  def perform(sqs_msg)
    puts "Shoryuken: '#{sqs_msg.body}'"

    sleep rand(1..10)
  end
end
