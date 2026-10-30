# frozen_string_literal: true

# This spec tests the body_parser option with :json beyond a single Hash.
#
# Expected behavior:
# - Arrays and scalars parse to their Ruby values (null -> nil)
# - Non-ASCII text and emoji stay intact in UTF-8

setup_sqs

queue_name = DT.uuid
create_test_queue(queue_name)
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')

Class.new do
  include Shoryuken::Worker

  shoryuken_options queue: queue_name, auto_delete: true, body_parser: :json

  def perform(sqs_msg, body)
    DT[:received] << [sqs_msg.body, body]
  end
end

non_ascii = { 'pl' => 'zażółć gęślą jaźń', 'emoji' => "\u{1F600}\u{1F680}", 'ja' => '日本語' }

expected = {
  '[1,"two",3.0,{"k":null}]' => [1, 'two', 3.0, { 'k' => nil }],
  '[]' => [],
  '42' => 42,
  '-1.5' => -1.5,
  '"str"' => 'str',
  'true' => true,
  'false' => false,
  'null' => nil,
  JSON.dump(non_ascii) => non_ascii
}

Shoryuken::Client.queues(queue_name).send_messages(
  entries: expected.keys.map { |body| { id: SecureRandom.uuid, message_body: body } }
)

poll_queues_until { DT[:received].size >= expected.size }

assert_equal(expected.size, DT[:received].size)
assert_equal(expected.keys.sort, DT[:received].map(&:first).sort)

DT[:received].each do |raw, body|
  assert_equal(expected[raw].class, body.class, "Wrong class for #{raw}")
  assert_equal(expected[raw], body, "Wrong value for #{raw}")
end

parsed_non_ascii = DT[:received].find { |raw, _| raw == JSON.dump(non_ascii) }.last
parsed_non_ascii.each_value do |value|
  assert_equal(Encoding::UTF_8, value.encoding)
  assert(value.valid_encoding?, "Invalid encoding in #{value.inspect}")
end

assert_equal(0, queue_size(queue_name))
