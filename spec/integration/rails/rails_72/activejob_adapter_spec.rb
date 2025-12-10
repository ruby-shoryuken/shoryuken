# frozen_string_literal: true

require 'active_job'
require 'active_job/queue_adapters/shoryuken_adapter'
require 'active_job/extensions'

# ActiveJob adapter integration tests for Rails 7.2

ActiveJob::Base.queue_adapter = :shoryuken

class EmailJob < ActiveJob::Base
  queue_as :default

  def perform(user_id, message)
    { user_id: user_id, message: message, sent_at: Time.current }
  end
end

class DataProcessingJob < ActiveJob::Base
  queue_as :high_priority

  def perform(data_file)
    "Processed: #{data_file}"
  end
end

class SerializationJob < ActiveJob::Base
  queue_as :default

  def perform(complex_data)
    complex_data.transform_values(&:upcase)
  end
end

# Test adapter setup
adapter = ActiveJob::Base.queue_adapter
assert_equal("ActiveJob::QueueAdapters::ShoryukenAdapter", adapter.class.name)

# Test singleton pattern
instance1 = ActiveJob::QueueAdapters::ShoryukenAdapter.instance
instance2 = ActiveJob::QueueAdapters::ShoryukenAdapter.instance
assert_equal(instance1.object_id, instance2.object_id)

# Test transaction commit hook (Rails 7.2+)
adapter_instance = ActiveJob::QueueAdapters::ShoryukenAdapter.new
assert(adapter_instance.respond_to?(:enqueue_after_transaction_commit?))
assert_equal(true, adapter_instance.enqueue_after_transaction_commit?)

# Test simple job enqueue
job_capture = JobCapture.new
job_capture.start_capturing

EmailJob.perform_later(1, 'Hello World')

assert_equal(1, job_capture.job_count)
job = job_capture.last_job
message_body = job[:message_body]
assert_equal('EmailJob', message_body['job_class'])
assert_equal([1, 'Hello World'], message_body['arguments'])
assert_equal('default', message_body['queue_name'])

# Test different queue
job_capture2 = JobCapture.new
job_capture2.start_capturing

DataProcessingJob.perform_later('large_dataset.csv')

job2 = job_capture2.last_job
message_body2 = job2[:message_body]
assert_equal('DataProcessingJob', message_body2['job_class'])
assert_equal('high_priority', message_body2['queue_name'])

# Test complex data serialization
complex_data = {
  'user' => { 'name' => 'John', 'age' => 30 },
  'preferences' => ['email', 'sms']
}

job_capture3 = JobCapture.new
job_capture3.start_capturing

SerializationJob.perform_later(complex_data)

job3 = job_capture3.last_job
message_body3 = job3[:message_body]
args_data = message_body3['arguments'].first
assert_equal('John', args_data['user']['name'])
assert_equal(30, args_data['user']['age'])

# Test shoryuken_class message attribute
job_capture4 = JobCapture.new
job_capture4.start_capturing

EmailJob.perform_later(1, 'Attributes test')

job4 = job_capture4.last_job
attributes = job4[:message_attributes]
expected_shoryuken_class = {
  string_value: "Shoryuken::ActiveJob::JobWrapper",
  data_type: 'String'
}
assert_equal(expected_shoryuken_class, attributes['shoryuken_class'])
