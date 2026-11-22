# frozen_string_literal: true

# This spec tests that with concurrency above 1 each log line carries only the
# logging context of the message its own thread processes.
#
# - Lines logged while a worker runs carry its `<worker>/<queue>/<message_id>`
# - All lines of one message come from one thread
# - Lines the manager and fetcher log between jobs carry no message context,
#   including the ones a processor thread logs right after its job
# - A logger set with `Shoryuken.logger=` gets all these lines

setup_sqs

FIRST_QUEUE = DT.queues[0]
SECOND_QUEUE = DT.queues[1]
MESSAGES_PER_QUEUE = 10

LINE_FORMAT = /\A\S+ \d+ TID-(?<tid>\S+)(?: (?<context>\S+))? (?<severity>[A-Z]+): (?<message>.*)\z/

create_test_queue(FIRST_QUEUE)
create_test_queue(SECOND_QUEUE)

Shoryuken.add_group('default', 5)
Shoryuken.add_queue(FIRST_QUEUE, 1, 'default')
Shoryuken.add_queue(SECOND_QUEUE, 1, 'default')

log = StringIO.new
logger = Logger.new(log)
logger.level = Logger::DEBUG
logger.formatter = Shoryuken::Logging::Pretty.new
Shoryuken.logger = logger

def record_job(sqs_msg)
  DT[:running] << sqs_msg.message_id
  DT[:max_running] << DT[:running].size
  Shoryuken.logger.info { "performing #{sqs_msg.message_id}" }
  sleep 0.2
  DT[:running].delete(sqs_msg.message_id)
  DT[:done] << sqs_msg.message_id
end

class FirstContextWorker
  include Shoryuken::Worker

  shoryuken_options queue: FIRST_QUEUE, auto_delete: true

  def perform(sqs_msg, _body)
    record_job(sqs_msg)
  end
end

class SecondContextWorker
  include Shoryuken::Worker

  shoryuken_options queue: SECOND_QUEUE, auto_delete: true

  def perform(sqs_msg, _body)
    record_job(sqs_msg)
  end
end

expected_contexts = {}

{ FIRST_QUEUE => FirstContextWorker, SECOND_QUEUE => SecondContextWorker }.each do |queue, worker|
  MESSAGES_PER_QUEUE.times do |i|
    id = Shoryuken::Client.queues(queue).send_message(message_body: "msg-#{i}").message_id
    expected_contexts[id] = "#{worker.name}/#{queue}/#{id}"
  end
end

poll_queues_until(timeout: 30) { DT[:done].size >= expected_contexts.size }

lines = log.string.lines.map(&:chomp).reject(&:empty?)
entries = lines.map do |line|
  match = LINE_FORMAT.match(line)
  assert(match, "Unexpected log line format: #{line}")
  match
end

assert(DT[:max_running].max > 1, "Expected jobs to overlap, at most #{DT[:max_running].max} ran at once")

job_entries = entries.select { |e| e[:message].start_with?('performing ') }
assert_equal(expected_contexts.size, job_entries.size)

job_entries.each do |entry|
  id = entry[:message].delete_prefix('performing ')
  assert_equal(expected_contexts[id], entry[:context], "Wrong context on: #{entry[0]}")
end

with_context = entries.select { |e| e[:context] }

with_context.each do |entry|
  assert_includes(expected_contexts.values, entry[:context])
end

with_context.group_by { |e| e[:context] }.each do |context, group|
  tids = group.map { |e| e[:tid] }.uniq
  assert_equal(1, tids.size, "Lines of #{context} came from threads #{tids}")
end

between_jobs = entries.select do |entry|
  entry[:message].start_with?(
    'Looking for new messages',
    'Fetcher for ',
    'Ready: ',
    'Assigning ',
    "Firing 'utilization_update'"
  )
end

assert(between_jobs.any?, 'Expected manager and fetcher lines between jobs')

between_jobs.each do |entry|
  refute(entry[:context], "Message context leaked onto: #{entry[0]}")
end

after_job_tids = between_jobs
                 .select { |e| e[:message].start_with?("Firing 'utilization_update'") }
                 .map { |e| e[:tid] }

job_entries.map { |e| e[:tid] }.uniq.each do |tid|
  assert_includes(after_job_tids, tid)
end
