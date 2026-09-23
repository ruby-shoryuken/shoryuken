# frozen_string_literal: true

# `shoryuken sqs dump`/`mv` drain a queue via CLI::SQS#find_all. With short
# polling, real (distributed) SQS routinely returns an empty batch while the
# queue still has messages, so find_all must use long polling and must not stop
# on the first empty response - otherwise dump/mv silently process only a
# fraction of the queue.
#
# ElasticMQ never produces those false-empties (nor visibility-timeout re-reads),
# so this drives find_all with scripted clients to verify the behavior
# deterministically.
#
# Lives under spec/integration (not spec/lib) because requiring bin/cli defines
# Shoryuken::CLI, and Shoryuken#server? is `defined?(Shoryuken::CLI)` - loading
# it in the unit suite would flip server? for every other spec. Integration
# specs each run in their own process, so that's contained here.

require 'thor'
require_relative '../../../bin/cli/base'
require_relative '../../../bin/cli/sqs'

Msg = Struct.new(:message_id, :receipt_handle)

# A scripted SQS client: hands out pre-canned batches in order (to simulate
# false-empties and visibility-timeout re-reads), ignoring max_number_of_messages
# and recording the wait_time_seconds it was asked for.
class ScriptedSqsClient
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

# A more realistic client backed by a flat list that honours
# max_number_of_messages, so the finite-limit / batch-sizing path can be driven.
class FlatSqsClient
  def initialize(messages)
    @messages = messages.dup
  end

  def receive_message(params)
    Struct.new(:messages).new(@messages.shift(params[:max_number_of_messages]))
  end
end

def find_all_with(client, limit)
  cli = Shoryuken::CLI::SQS.allocate
  cli.instance_variable_set(:@_sqs, client)

  collected = []
  count = cli.send(:find_all, 'http://example.com/q', limit) { |msg| collected << msg }
  [collected, count]
end

# --- Drains past a false-empty batch, using long polling -------------------
client = ScriptedSqsClient.new(
  [
    [Msg.new('a'), Msg.new('b'), Msg.new('c')],
    [Msg.new('d'), Msg.new('e')],
    [],                       # false-empty while 'f' is still queued
    [Msg.new('f')]
  ]
)
collected, = find_all_with(client, Float::INFINITY)

assert_equal(%w[a b c d e f], collected.map(&:message_id), 'find_all should drain past a false-empty batch')
assert(
  client.wait_times.any? && client.wait_times.all? { |w| w && w.positive? },
  "find_all should use long polling, saw wait_time_seconds: #{client.wait_times.uniq.inspect}"
)

# --- Does not re-yield a message that reappears after its visibility timeout ---
# 'a' is handed back on a later receive (its visibility timeout lapsed before
# dump/mv deleted it). find_all must yield and count it only once.
reappearing = ScriptedSqsClient.new(
  [
    [Msg.new('a'), Msg.new('b')],
    [Msg.new('a')],           # re-read of 'a' while it is still in the queue
    [Msg.new('c')]
  ]
)
collected, count = find_all_with(reappearing, Float::INFINITY)

assert_equal(%w[a b c], collected.map(&:message_id), 'find_all must not re-yield a re-read message')
assert_equal(3, count, 'find_all count must not double-count a re-read message')

# --- Retains the newest receipt handle for a re-read message ----------------
# SQS only honors the most recently received receipt handle for deletion, and
# dump/mv batch_delete after the drain, so the yielded (and later deleted)
# message must carry the handle from the latest receive, not the first.
handles = ScriptedSqsClient.new(
  [
    [Msg.new('x', 'rh-x-1'), Msg.new('y', 'rh-y')],
    [Msg.new('x', 'rh-x-2')], # re-read of 'x' with a fresh handle
    [Msg.new('z', 'rh-z')]
  ]
)
collected, = find_all_with(handles, Float::INFINITY)

x = collected.find { |msg| msg.message_id == 'x' }
assert_equal('rh-x-2', x.receipt_handle, 'find_all must retain the newest receipt handle for a re-read message')
assert_equal(%w[x y z], collected.map(&:message_id), 'a re-read must not be yielded twice')

# --- Stops at a finite limit without over-fetching -------------------------
flat = FlatSqsClient.new((1..25).map { |i| Msg.new("m#{i}") })
collected, count = find_all_with(flat, 15)

assert_equal(15, count, 'find_all must stop once the limit is reached')
assert_equal(
  (1..15).map { |i| "m#{i}" },
  collected.map(&:message_id),
  'find_all must yield exactly the first `limit` messages'
)
