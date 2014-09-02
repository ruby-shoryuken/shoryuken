module Shoryuken
  class HelloWorker
    include Shoryuken::Worker

    shoryuken_options queue: 'my_queue1'

    def perform(sqs_msg, firstname, lastname)
      puts "Hello #{firstname} #{lastname}"

      sqs_msg.delete
    end
  end
end
