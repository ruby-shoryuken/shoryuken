class SidekiqWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'sidekiq', auto_delete: true

  def perform(sqs_msg)
    puts "Sidekiq: '#{sqs_msg.body}'"

    sleep rand(0..1)
  end
end
