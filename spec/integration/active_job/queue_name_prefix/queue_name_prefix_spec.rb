# frozen_string_literal: true

# This spec tests that, with active_job_queue_name_prefixing, the environment
# loader applies ActiveJob's queue_name_prefix to queue names, but not to
# queues given as a URL or an ARN.
#
# Expected behavior: `-q <name>` polls `<prefix>_<name>`, the queue ActiveJob
# sends the job to, so the job is performed. Queues given as an https URL or
# an ARN are polled as given, and their workers process their messages.
#
# Regression: #57 (CHANGELOG v2.0.2) - the prefix was not applied, so the
# process polled a queue that ActiveJob never sent to.
# Regression: #309 (CHANGELOG v5.2.2) - the prefix was put in front of URL
# and ARN queues, which broke them.

# ElasticMQ serves any queue URL host, but this SDK plugin sends each request
# to the host of its queue URL, which for https/ARN queues is amazonaws.com.
Aws::SQS::Client.remove_plugin(Aws::SQS::Plugins::QueueUrls)

setup_sqs
setup_active_job

ActiveJob::Base.queue_name_prefix = 'prefix'
Shoryuken.active_job_queue_name_prefixing = true

job_queue = DT.uuid
url_queue = DT.uuid
arn_queue = DT.uuid
create_test_queue("prefix_#{job_queue}")
create_test_queue(url_queue)
create_test_queue(arn_queue)

url = "https://sqs.us-east-1.amazonaws.com/000000000000/#{url_queue}"
arn = "arn:aws:sqs:us-east-1:000000000000:#{arn_queue}"

class PrefixedJob < ActiveJob::Base
  def perform(body)
    DT[:performed] << [:job, body]
  end
end

PrefixedJob.queue_as(job_queue)

[[url, :url], [arn, :arn]].each do |queue, kind|
  Class.new do
    include Shoryuken::Worker

    shoryuken_options queue: queue, auto_delete: true

    define_method(:perform) { |_sqs_msg, body| DT[:performed] << [kind, body] }
  end
end

Shoryuken::EnvironmentLoader.setup_options(queues: [[job_queue, 1], [url, 1], [arn, 1]]).load

assert_equal(["prefix_#{job_queue}", url, arn], Shoryuken.ungrouped_queues)

PrefixedJob.perform_later('to the prefixed queue')
Shoryuken::Client.queues(url).send_message(message_body: 'to the url queue')
Shoryuken::Client.queues(arn).send_message(message_body: 'to the arn queue')

poll_queues_until(timeout: 20) { DT[:performed].size >= 3 }

assert_equal(
  [[:arn, 'to the arn queue'], [:job, 'to the prefixed queue'], [:url, 'to the url queue']],
  DT[:performed].sort
)

delete_test_queue("prefix_#{job_queue}")
delete_test_queue(url_queue)
delete_test_queue(arn_queue)
