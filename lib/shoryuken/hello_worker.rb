class HelloWorker
  def perform(sqs_msg)
    puts sqs_msg.body

    sqs_msg.delete
  end
end
