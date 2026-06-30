# frozen_string_literal: true

# `shoryuken sqs dump`/`mv` drain a queue via CLI::SQS#find_all. With short
# polling, real (distributed) SQS routinely returns an empty batch while the
# queue still has messages, so find_all must use long polling and must not stop
# on the first empty response - otherwise dump/mv silently process only a
# fraction of the queue.
#
# ElasticMQ never produces those false-empties, so this drives find_all with a
# scripted client to verify the behavior deterministically.
#
# Lives under spec/integration (not spec/lib) because requiring bin/cli defines
# Shoryuken::CLI, and Shoryuken#server? is `defined?(Shoryuken::CLI)` - loading
# it in the unit suite would flip server? for every other spec. Integration
# specs each run in their own process, so that's contained here.

require 'thor'
require_relative '../../../bin/cli/base'
require_relative '../../../bin/cli/sqs'

# A scripted SQS client: hands out batches in order (including a false-empty in
# the middle), recording the wait_time_seconds it was asked for.
class ScriptedSqsClient
  Msg = Struct.new(:message_id)

  attr_reader :wait_times

  def initialize(batches)
    @batches = batches.dup
    @wait_times = []
  end

  def receive_message(params)
    @wait_times << params[:wait_time_seconds]
    Struct.new(:messages).new(@batches.shift || [])
  end
end

m = ScriptedSqsClient::Msg
script = [
  [m.new('a'), m.new('b'), m.new('c')],
  [m.new('d'), m.new('e')],
  [],                       # false-empty while 'f' is still queued
  [m.new('f')]
]
client = ScriptedSqsClient.new(script)

cli = Shoryuken::CLI::SQS.allocate
cli.instance_variable_set(:@_sqs, client)

collected = []
cli.send(:find_all, 'http://example.com/q', Float::INFINITY) { |msg| collected << msg.message_id }

# Drains everything, including 'f' after the false-empty - short polling would
# have stopped at the first empty batch and missed it.
assert_equal(%w[a b c d e f], collected, 'find_all should drain past a false-empty batch')

# And it long-polls rather than short-polls.
assert(
  client.wait_times.any? && client.wait_times.all? { |w| w && w.positive? },
  "find_all should use long polling, saw wait_time_seconds: #{client.wait_times.uniq.inspect}"
)
