# frozen_string_literal: true

# This spec tests worker lifecycle including graceful shutdown with in-flight
# messages, worker registration and discovery, worker inheritance behavior,
# dynamic queue names (callable), and concurrent workers on the same queue.

RSpec.describe 'Worker Lifecycle Integration' do
  include_context 'localstack'

  let(:queue_name) { "lifecycle-test-#{SecureRandom.uuid}" }

  before do
    create_test_queue(queue_name)
    Shoryuken.add_group('default', 1)
    Shoryuken.add_queue(queue_name, 1, 'default')
  end

  after do
    delete_test_queue(queue_name)
    Shoryuken.worker_registry.clear
    Shoryuken.groups.clear
  end

  describe 'Graceful shutdown' do
    it 'completes in-flight messages before shutdown' do
      worker = create_slow_worker(queue_name, processing_time: 2)
      worker.received_messages = []
      worker.completed_messages = []

      Shoryuken::Client.queues(queue_name).send_message(message_body: 'shutdown-test')

      launcher = Shoryuken::Launcher.new
      launcher.start

      # Wait for message to start processing
      sleep 1

      # Initiate shutdown while message is still processing
      stop_thread = Thread.new { launcher.stop }

      # Wait for graceful shutdown
      stop_thread.join(10)

      expect(worker.completed_messages.size).to eq 1
    end

    it 'stops accepting new messages after shutdown signal' do
      worker = create_simple_worker(queue_name)
      worker.received_messages = []

      launcher = Shoryuken::Launcher.new
      launcher.start

      # Immediately stop
      launcher.stop

      # Send message after stop
      Shoryuken::Client.queues(queue_name).send_message(message_body: 'after-shutdown')

      sleep 2

      # Message should not be processed
      expect(worker.received_messages.size).to eq 0
    end
  end

  describe 'Worker registration' do
    it 'registers worker for queue' do
      worker_class = create_simple_worker(queue_name)

      registered = Shoryuken.worker_registry.workers(queue_name)
      expect(registered).to include(worker_class)
    end

    it 'replaces existing worker when registering same queue (non-batch)' do
      worker1 = Class.new do
        include Shoryuken::Worker

        def perform(sqs_msg, body); end
      end

      worker2 = Class.new do
        include Shoryuken::Worker

        def perform(sqs_msg, body); end
      end

      # Set options manually without triggering auto-registration
      worker1.get_shoryuken_options['queue'] = 'multi-worker-queue'
      worker1.get_shoryuken_options['auto_delete'] = true
      worker1.get_shoryuken_options['batch'] = false

      worker2.get_shoryuken_options['queue'] = 'multi-worker-queue'
      worker2.get_shoryuken_options['auto_delete'] = true
      worker2.get_shoryuken_options['batch'] = false

      Shoryuken.register_worker('multi-worker-queue', worker1)
      Shoryuken.register_worker('multi-worker-queue', worker2)

      # Second registration replaces the first one
      registered = Shoryuken.worker_registry.workers('multi-worker-queue')
      expect(registered.size).to eq 1
      expect(registered.first).to eq worker2
    end
  end

  describe 'Worker inheritance' do
    it 'inherits options from parent worker' do
      parent_worker = Class.new do
        include Shoryuken::Worker
        shoryuken_options auto_delete: true, batch: false
      end

      child_worker = Class.new(parent_worker) do
        shoryuken_options queue: 'child-queue'
      end

      options = child_worker.get_shoryuken_options
      expect(options['auto_delete']).to be true
      expect(options['batch']).to be false
      expect(options['queue']).to eq 'child-queue'
    end

    it 'allows child to override parent options' do
      parent_worker = Class.new do
        include Shoryuken::Worker
        shoryuken_options auto_delete: true, batch: false
      end

      child_worker = Class.new(parent_worker) do
        shoryuken_options auto_delete: false, queue: 'override-queue'
      end

      options = child_worker.get_shoryuken_options
      expect(options['auto_delete']).to be false
      expect(options['queue']).to eq 'override-queue'
    end
  end

  describe 'Dynamic queue names' do
    it 'supports callable queue names' do
      dynamic_queue = "dynamic-#{SecureRandom.uuid}"

      create_test_queue(dynamic_queue)

      begin
        worker_class = Class.new do
          include Shoryuken::Worker

          class << self
            attr_accessor :received_messages
          end

          shoryuken_options auto_delete: true, batch: false

          def perform(sqs_msg, body)
            self.class.received_messages ||= []
            self.class.received_messages << body
          end
        end

        # Set queue as callable
        worker_class.get_shoryuken_options['queue'] = -> { dynamic_queue }
        worker_class.received_messages = []

        Shoryuken.add_queue(dynamic_queue, 1, 'default')
        Shoryuken.register_worker(dynamic_queue, worker_class)

        Shoryuken::Client.queues(dynamic_queue).send_message(message_body: 'dynamic-msg')

        poll_queues_until { worker_class.received_messages.size >= 1 }

        expect(worker_class.received_messages.size).to eq 1
      ensure
        delete_test_queue(dynamic_queue)
      end
    end
  end

  describe 'Concurrent workers' do
    it 'processes messages concurrently' do
      Shoryuken.groups.clear
      Shoryuken.add_group('concurrent', 3) # 3 concurrent workers
      Shoryuken.add_queue(queue_name, 1, 'concurrent') # Add queue to the new group

      worker = create_slow_worker(queue_name, processing_time: 1)
      worker.received_messages = []
      worker.start_times = []

      # Send multiple messages
      5.times do |i|
        Shoryuken::Client.queues(queue_name).send_message(message_body: "concurrent-#{i}")
      end

      sleep 1

      poll_queues_until(timeout: 20) { worker.received_messages.size >= 5 }

      expect(worker.received_messages.size).to eq 5

      # Check for concurrent processing by looking at overlapping start times
      # With concurrency, some messages should start processing close together
      time_diffs = worker.start_times.sort.each_cons(2).map { |a, b| b - a }
      expect(time_diffs.any? { |diff| diff < 0.5 }).to be true
    end
  end

  private

  def create_slow_worker(queue, processing_time:)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_messages, :completed_messages, :start_times, :processing_time
      end

      def perform(sqs_msg, body)
        self.class.start_times ||= []
        self.class.start_times << Time.now

        self.class.received_messages ||= []
        self.class.received_messages << body

        sleep self.class.processing_time

        self.class.completed_messages ||= []
        self.class.completed_messages << body
      end
    end

    # Set options before registering to avoid default queue conflicts
    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.get_shoryuken_options['auto_delete'] = true
    worker_class.get_shoryuken_options['batch'] = false
    worker_class.processing_time = processing_time
    worker_class.received_messages = []
    worker_class.completed_messages = []
    worker_class.start_times = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end

  def create_simple_worker(queue)
    worker_class = Class.new do
      include Shoryuken::Worker

      class << self
        attr_accessor :received_messages
      end

      def perform(sqs_msg, body)
        self.class.received_messages ||= []
        self.class.received_messages << body
      end
    end

    # Set options before registering to avoid default queue conflicts
    worker_class.get_shoryuken_options['queue'] = queue
    worker_class.get_shoryuken_options['auto_delete'] = true
    worker_class.get_shoryuken_options['batch'] = false
    worker_class.received_messages = []
    Shoryuken.register_worker(queue, worker_class)
    worker_class
  end
end
