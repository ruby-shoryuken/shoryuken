# frozen_string_literal: true

# This spec tests a failing message on a FIFO queue with two message groups.
#
# The failing message stays in flight until the visibility timeout and holds its group, so no
# later message of that group runs before the retry. The other group keeps processing while the first one waits.
# After the retry succeeds, the held group runs in send order.

setup_sqs

queue_name = "#{DT.uuid}.fifo"
create_fifo_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })
Shoryuken.add_group('default', 4)
Shoryuken.add_queue(queue_name, 1, 'default')

worker_class = Class.new do
  include Shoryuken::Worker

  shoryuken_options queue: queue_name, auto_delete: true, batch: false

  def perform(_sqs_msg, body)
    DT[:attempts] << body

    return unless body == 'a-0' && DT[:attempts].count('a-0') == 1

    raise 'first attempt fails'
  end
end
Shoryuken.register_worker(queue_name, worker_class)

queue_url = Shoryuken::Client.sqs.get_queue_url(queue_name: queue_name).queue_url

%w[a-0 b-0 a-1 b-1 a-2 b-2].each do |body|
  Shoryuken::Client.sqs.send_message(
    queue_url: queue_url,
    message_body: body,
    message_group_id: body[0],
    message_deduplication_id: SecureRandom.uuid
  )
end

poll_queues_until(timeout: 20) { DT[:attempts].count { |body| body.start_with?('a-') } >= 4 }

attempts = DT[:attempts]
retry_index = attempts.each_index.select { |i| attempts[i] == 'a-0' }.last

assert_equal(%w[a-0 a-0 a-1 a-2], attempts.grep(/\Aa-/))
assert_equal(%w[b-0 b-1 b-2], attempts.grep(/\Ab-/))
assert(
  attempts.index('b-2') < retry_index,
  "group b should finish while group a waits for its retry, got: #{attempts.inspect}"
)
