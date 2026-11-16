# frozen_string_literal: true

# This spec tests the options of the `shoryuken sqs` commands against ElasticMQ.
#
# `dump -n` dumps that many messages and `--no-delete` keeps them in the queue; `requeue --batch-size` and `mv -n`
# with `--no-delete` or `-d` take their values; `ls -w -n` lists the queues again after the interval; `create -a`
# sets every given attribute; `-e`/`--endpoint` defaults to `SHORYUKEN_SQS_ENDPOINT`.

setup_sqs

endpoint = SHORYUKEN_ENV['AWS_ENDPOINT_URL_SQS']

def queue_attribute(queue, name)
  Shoryuken::Client.sqs.get_queue_attributes(queue_url: queue_url(queue), attribute_names: [name]).attributes[name]
end

def assert_success(args, message)
  status, output = run_shoryuken_sqs(*args)
  assert(status.success?, "#{args.join(' ')} must succeed, got: #{output}")
  assert_includes(output, message)
end

def assert_watch(source)
  status, output = run_shoryuken_sqs_until('ls', source, '-w', '-n', '0.2', signal: 'INT') do |log|
    log.scan('Messages Available').size >= 2
  end
  assert(output.scan(/^#{Regexp.escape(source)}\s+0\s/).size >= 2, "ls -w must list again, got: #{output}")
  assert(status.success?, "ls -w must exit 0 on INT, got: #{output}")
end

def assert_endpoint_default(source, endpoint)
  status, output = run_shoryuken_command_until_exit(
    'sqs', 'ls', source,
    env: { 'SHORYUKEN_SQS_ENDPOINT' => endpoint, 'AWS_ENDPOINT_URL_SQS' => 'http://localhost:1' }
  )
  assert(status.success?, "ls must use SHORYUKEN_SQS_ENDPOINT, got: #{output}")
  assert_includes(output, source)

  status, output = run_shoryuken_command_until_exit(
    'sqs', 'ls', source, "--endpoint=#{endpoint}", env: { 'SHORYUKEN_SQS_ENDPOINT' => 'http://localhost:1' }
  )
  assert(status.success?, "--endpoint must win over SHORYUKEN_SQS_ENDPOINT, got: #{output}")
  assert_includes(output, source)
end

# Messages come back at once after a receive, so `mv` and `dump` see the ones a `--no-delete` call left
with_queue_and_dir(attributes: { 'VisibilityTimeout' => '0' }) do |source, dir|
  with_queue_and_dir do |target, _target_dir|
    3.times { |i| Shoryuken::Client.sqs.send_message(queue_url: queue_url(source), message_body: "message #{i}") }

    assert_success(['dump', source, '-n', '2', '--no-delete', '-p', dir], 'with 2 messages')
    path = Dir[File.join(dir, '*.jsonl')].first
    assert_equal(2, File.readlines(path).size, 'dump -n 2 must dump 2 messages')
    assert_equal(3, queue_size(source), 'dump --no-delete must keep the messages')

    assert_success(['requeue', target, path, '--batch-size', '1'], "Requeued 2 messages from #{path} to #{target}")
    assert_equal(2, queue_size(target))

    assert_success(['mv', source, target, '--number=1', '--no-delete'], "Moved 1 messages from #{source} to #{target}")
    assert_equal([3, 3], [queue_size(source), queue_size(target)], 'mv --no-delete must keep the moved message')

    assert_success(['mv', source, target, '-n', '1', '-d'], "Moved 1 messages from #{source} to #{target}")
    assert_equal([2, 4], [queue_size(source), queue_size(target)], 'mv -d must delete the moved message')

    all = File.join(dir, 'all')
    FileUtils.mkdir_p(all)
    assert_success(['dump', source, '--delete', '--path', all], 'with 2 messages')
    assert_equal(0, queue_size(source), 'dump --delete must delete the messages')

    assert_watch(source)
    assert_endpoint_default(source, endpoint)
  end
end

with_queue_name do |queue|
  assert_success(['create', queue, '-a', 'VisibilityTimeout:45', 'DelaySeconds:2'], "Queue #{queue} was successfully")
  assert_equal(%w[45 2], [queue_attribute(queue, 'VisibilityTimeout'), queue_attribute(queue, 'DelaySeconds')])
end

with_queue_name do |queue|
  assert_success(['create', queue, '--attributes=DelaySeconds:3'], "Queue #{queue} was successfully")
  assert_equal('3', queue_attribute(queue, 'DelaySeconds'))
end
