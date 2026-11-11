# frozen_string_literal: true

# This spec tests that, with active_job_queue_name_prefixing, the environment
# loader applies ActiveJob's queue_name_prefix to queue names, but not to
# queues given as an http or https URL or an ARN, both in `queues` and in
# `groups`.
#
# A queue name `<name>` is polled as `<prefix>_<name>`, the queue ActiveJob
# sends the job to, so the job is performed. Queues given as an http URL (as
# ElasticMQ or LocalStack return), an https URL or an ARN are polled as given,
# and their workers process their messages.
#
# Regression: #57 (CHANGELOG v2.0.2) - the prefix was not applied, so the
# process polled a queue that ActiveJob never sent to.
# Regression: #667 (CHANGELOG v5.2.2) - the prefix was put in front of URL and
# ARN queues (reported with a `groups` config), which broke them.
# It used to put the prefix in front of http URL queues.

# ElasticMQ serves any queue URL host, but this SDK plugin sends each request
# to the host of its queue URL, which for https/ARN queues is amazonaws.com.
Aws::SQS::Client.remove_plugin(Aws::SQS::Plugins::QueueUrls)

setup_sqs
setup_active_job

ActiveJob::Base.queue_name_prefix = 'prefix'
Shoryuken.active_job_queue_name_prefixing = true

job_queue, url_queue, group_job_queue, group_arn_queue, http_url_queue = DT.uuids(5)
create_test_queue("prefix_#{job_queue}")
create_test_queue("prefix_#{group_job_queue}")
create_test_queue(url_queue)
create_test_queue(group_arn_queue)
create_test_queue(http_url_queue)

url = "https://sqs.us-east-1.amazonaws.com/000000000000/#{url_queue}"
http_url = Shoryuken::Client.sqs.get_queue_url(queue_name: http_url_queue).queue_url
arn = "arn:aws:sqs:us-east-1:000000000000:#{group_arn_queue}"

class PrefixedJob < ActiveJob::Base
  def perform(body)
    DT[:performed] << [:job, body]
  end
end

[[url, :url], [arn, :arn], [http_url, :http_url]].each do |queue, kind|
  Class.new do
    include Shoryuken::Worker

    shoryuken_options queue: queue, auto_delete: true

    define_method(:perform) { |_sqs_msg, body| DT[:performed] << [kind, body] }
  end
end

Shoryuken::EnvironmentLoader.setup_options(
  queues: [[job_queue, 1], [url, 1]],
  groups: { 'grouped' => { concurrency: 1, queues: [[group_job_queue, 1], [arn, 1], [http_url, 1]] } }
).load

assert(http_url.start_with?('http://'))
assert_equal(["prefix_#{job_queue}", url], Shoryuken.groups['default'][:queues])
assert_equal(["prefix_#{group_job_queue}", arn, http_url], Shoryuken.groups['grouped'][:queues])

PrefixedJob.set(queue: job_queue).perform_later('to the prefixed queue')
PrefixedJob.set(queue: group_job_queue).perform_later('to the prefixed group queue')
Shoryuken::Client.queues(url).send_message(message_body: 'to the url queue')
Shoryuken::Client.queues(arn).send_message(message_body: 'to the arn group queue')
Shoryuken::Client.queues(http_url).send_message(message_body: 'to the http url group queue')

poll_queues_until(timeout: 20) { DT[:performed].size >= 5 }

assert_equal(
  [
    [:arn, 'to the arn group queue'],
    [:http_url, 'to the http url group queue'],
    [:job, 'to the prefixed group queue'],
    [:job, 'to the prefixed queue'],
    [:url, 'to the url queue']
  ],
  DT[:performed].sort
)

delete_test_queue("prefix_#{job_queue}")
delete_test_queue("prefix_#{group_job_queue}")
delete_test_queue(url_queue)
delete_test_queue(group_arn_queue)
delete_test_queue(http_url_queue)
