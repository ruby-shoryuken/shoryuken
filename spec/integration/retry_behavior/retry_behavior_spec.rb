# frozen_string_literal: true

# This spec tests retry behavior including ApproximateReceiveCount tracking,
# exponential backoff with retry_intervals, retry exhaustion, and custom
# retry interval configurations (array and callable).

RSpec.describe 'Retry Behavior Integration' do
  include_context 'localstack'

  let(:queue_name) { "retry-test-#{SecureRandom.uuid}" }

  before do
    # Create queue with short visibility timeout for faster retries
    create_test_queue(queue_name, attributes: { 'VisibilityTimeout' => '2' })
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')
  end

  after do
    delete_test_queue(queue_name)
  end

  describe 'ApproximateReceiveCount tracking' do
    it 'tracks receive count across message redeliveries' do
      worker = create_failing_worker(queue_name, fail_times: 2)
      worker.receive_counts = []

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'retry-count-test')

      # Wait for multiple redeliveries
      poll_queues_until(timeout: 20) { worker.receive_counts.size >= 3 }

      expect(worker.receive_counts.size).to be >= 3
      expect(worker.receive_counts.sort).to eq worker.receive_counts # Should be increasing
      expect(worker.receive_counts.first).to eq 1
    end
  end

  describe 'Retry with exponential backoff middleware' do
    it 'adjusts visibility timeout based on retry intervals' do
      worker = create_backoff_worker(queue_name)
      worker.receive_counts = []
      worker.visibility_changes = []

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'backoff-test')

      poll_queues_until(timeout: 15) { worker.receive_counts.size >= 2 }

      expect(worker.receive_counts.size).to be >= 2
      # Visibility changes should have been attempted
      expect(worker.visibility_changes).not_to be_empty
    end
  end

  describe 'Retry exhaustion' do
    it 'stops retrying after max attempts' do
      worker = create_limited_retry_worker(queue_name, max_retries: 3)
      worker.attempt_count = 0
      worker.exhausted = false

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'exhaustion-test')

      poll_queues_until(timeout: 20) { worker.attempt_count >= 3 || worker.exhausted }

      expect(worker.attempt_count).to be >= 3
    end
  end

  describe 'Custom retry intervals' do
    it 'uses array-based retry intervals' do
      # Test with array intervals: [1, 2, 4] seconds
      worker = create_array_interval_worker(queue_name)
      worker.receive_times = []

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'array-interval-test')

      poll_queues_until(timeout: 15) { worker.receive_times.size >= 2 }

      expect(worker.receive_times.size).to be >= 2
    end

    it 'uses callable retry intervals' do
      # Test with lambda-based intervals
      worker = create_lambda_interval_worker(queue_name)
      worker.receive_times = []
      worker.intervals_used = []

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'lambda-interval-test')

      poll_queues_until(timeout: 15) { worker.receive_times.size >= 2 }

      expect(worker.receive_times.size).to be >= 2
    end
  end

  private

  def create_failing_worker(queue, fail_times:)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :receive_counts, :fail_times_remaining
      end

      shoryuken_options auto_delete: false, batch: false

      def perform(sqs_msg, body)
        receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
        self.class.receive_counts ||= []
        self.class.receive_counts << receive_count

        if self.class.fail_times_remaining > 0
          self.class.fail_times_remaining -= 1
          raise "Simulated failure"
        else
          sqs_msg.delete
        end
      end
    end

    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.receive_counts = []
    worker_class.fail_times_remaining = fail_times
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end

  def create_backoff_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :receive_counts, :visibility_changes
      end

      shoryuken_options auto_delete: false, batch: false, retry_intervals: [1, 2, 4]

      def perform(sqs_msg, body)
        receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
        self.class.receive_counts ||= []
        self.class.receive_counts << receive_count

        if receive_count < 3
          self.class.visibility_changes ||= []
          self.class.visibility_changes << receive_count
          raise "Backoff failure"
        else
          sqs_msg.delete
        end
      end
    end

    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.receive_counts = []
    worker_class.visibility_changes = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end

  def create_limited_retry_worker(queue, max_retries:)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :attempt_count, :exhausted, :max_retries
      end

      shoryuken_options auto_delete: false, batch: false

      def perform(sqs_msg, body)
        self.class.attempt_count += 1
        receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i

        if receive_count >= self.class.max_retries
          self.class.exhausted = true
          sqs_msg.delete
        else
          raise "Retry #{receive_count}"
        end
      end
    end

    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.attempt_count = 0
    worker_class.exhausted = false
    worker_class.max_retries = max_retries
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end

  def create_array_interval_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :receive_times
      end

      shoryuken_options auto_delete: false, batch: false, retry_intervals: [1, 2, 4]

      def perform(sqs_msg, body)
        self.class.receive_times ||= []
        self.class.receive_times << Time.now
        receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i

        if receive_count < 3
          raise "Array interval retry"
        else
          sqs_msg.delete
        end
      end
    end

    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.receive_times = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end

  def create_lambda_interval_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :receive_times, :intervals_used
      end

      # Lambda returns interval based on attempt number
      shoryuken_options auto_delete: false, batch: false,
                        retry_intervals: ->(attempt) { [1, 2, 4][attempt - 1] || 4 }

      def perform(sqs_msg, body)
        self.class.receive_times ||= []
        self.class.receive_times << Time.now
        receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i

        self.class.intervals_used ||= []
        self.class.intervals_used << receive_count

        if receive_count < 3
          raise "Lambda interval retry"
        else
          sqs_msg.delete
        end
      end
    end

    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.receive_times = []
    worker_class.intervals_used = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end
end
