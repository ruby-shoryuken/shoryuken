class SidekiqWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'sidekiq', delete: true

  def perform(sqs_msg)
    puts "Sidekiq: '#{sqs_msg.body}'"

    sleep rand(0..1)
  end
end
