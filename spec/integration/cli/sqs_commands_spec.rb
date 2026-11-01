# frozen_string_literal: true

# This spec tests `shoryuken sqs create`, `ls`, `purge` and `delete` against ElasticMQ.
#
# `create` creates the queue with the given attributes, and as a FIFO queue when its name ends
# with `.fifo`. `ls PREFIX` lists only the queues whose name starts with the prefix, each with its full name (also
# one longer than 40 characters) and its available and in-flight message counts. `purge` deletes the messages of a
# queue and keeps it, and `delete` deletes the queue.
#
# Regression: #366 - `ls` cut queue names longer than 40 characters.

setup_sqs

LONG_SUFFIX = "-#{'long-queue-name' * 2}".freeze

def queue_attribute(queue, name)
  Shoryuken::Client.sqs.get_queue_attributes(queue_url: queue_url(queue), attribute_names: [name]).attributes[name]
end

def queue_exists?(queue)
  queue_url(queue)
  true
rescue Aws::SQS::Errors::NonExistentQueue, Aws::SQS::Errors::QueueDoesNotExist
  false
end

def ls(prefix)
  status, output = run_shoryuken_sqs('ls', prefix)
  assert(status.success?, "ls must succeed, got: #{output}")
  output
end

def create_queues(long, fifo)
  status, output = run_shoryuken_sqs('create', long, '-a', 'VisibilityTimeout:45')
  assert(status.success?, "create must succeed, got: #{output}")
  assert_includes(output, "Queue #{long} was successfully created. Queue URL #{queue_url(long)}")
  assert_equal('45', queue_attribute(long, 'VisibilityTimeout'), 'create must set the given attributes')

  status, output = run_shoryuken_sqs('create', fifo)
  assert(status.success?, "create of a FIFO queue must succeed, got: #{output}")
  assert_equal('true', queue_attribute(fifo, 'FifoQueue'), 'create must make a .fifo queue a FIFO queue')
end

def list_queues(base, long, fifo)
  3.times { |i| Shoryuken::Client.sqs.send_message(queue_url: queue_url(long), message_body: "message #{i}") }

  output = ls(base)
  assert(output.match?(/^#{Regexp.escape(long)}\s+3\s+0\s/), "ls must list #{long} in full with 3 messages: #{output}")
  assert(output.match?(/^#{Regexp.escape(fifo)}\s+0\s+0\s/), "ls must list #{fifo} with 0 messages: #{output}")

  output = ls("#{base}-")
  assert_includes(output, long)
  refute(output.include?(fifo), "ls must list only the queues with the prefix, got: #{output}")
end

def purge_queue(long)
  status, output = run_shoryuken_sqs('purge', long)
  assert(status.success?, "purge must succeed, got: #{output}")
  assert_includes(output, "Purge request sent for #{long}")
  assert_equal(0, queue_size(long), 'purge must delete the messages')
  assert(queue_exists?(long), 'purge must keep the queue')
end

def delete_queues(long, fifo)
  [long, fifo].each do |queue|
    status, output = run_shoryuken_sqs('delete', queue)
    assert(status.success?, "delete must succeed, got: #{output}")
    assert_includes(output, "Queue #{queue} was successfully deleted")
    refute(queue_exists?(queue), "delete must delete #{queue}")
    refute(ls(queue).include?(queue), "ls must not list the deleted #{queue}")
  end
end

base = DT.uuid

with_queue_name(base: base, suffix: LONG_SUFFIX) do |long|
  with_queue_name(base: base, suffix: '.fifo') do |fifo|
    assert(long.size > 40, 'the long queue name must be longer than the 40 characters ls used to print')

    create_queues(long, fifo)
    list_queues(base, long, fifo)
    purge_queue(long)
    delete_queues(long, fifo)
  end
end
