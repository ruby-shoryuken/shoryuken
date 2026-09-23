# frozen_string_literal: true

RSpec.describe Shoryuken::Client do
  let(:credentials) { Aws::Credentials.new('access_key_id', 'secret_access_key') }
  let(:sqs)         { Aws::SQS::Client.new(stub_responses: true, credentials: credentials) }
  let(:queue_name)  { 'shoryuken' }
  let(:queue_url)   { 'https://eu-west-1.amazonaws.com:6059/123456789012/shoryuken' }

  describe '.queue' do
    before do
      described_class.sqs = sqs
    end

    it 'memoizes queues' do
      sqs.stub_responses(:get_queue_url, { queue_url: queue_url }, queue_url: 'xyz')

      expect(Shoryuken::Client.queues(queue_name).url).to eq queue_url
      expect(Shoryuken::Client.queues(queue_name).url).to eq queue_url
    end

    it 'constructs each queue only once under concurrent first access' do
      allow(described_class).to receive(:sqs).and_return(sqs)

      construction_count = Shoryuken::Helpers::AtomicCounter.new(0)
      allow(Shoryuken::Queue).to receive(:new) do
        construction_count.increment
        # Mimic the SQS API latency during construction. sleep releases the GVL,
        # so without synchronization every concurrent caller builds its own queue.
        sleep 0.05
        instance_double(Shoryuken::Queue)
      end

      threads = Array.new(10) { Thread.new { described_class.queues('concurrent') } }
      threads.each(&:join)

      expect(construction_count.value).to eq(1)
    end

    it 'rebuilds cached queues after the sqs client is replaced' do
      allow(described_class).to receive(:sqs).and_return(sqs)

      construction_count = Shoryuken::Helpers::AtomicCounter.new(0)
      allow(Shoryuken::Queue).to receive(:new) do
        construction_count.increment
        instance_double(Shoryuken::Queue)
      end

      described_class.queues(queue_name)
      described_class.queues(queue_name)
      expect(construction_count.value).to eq(1)

      described_class.sqs = sqs

      described_class.queues(queue_name)
      expect(construction_count.value).to eq(2)
    end

    it 'does not cache a queue built with the previous client while it is being replaced' do
      old_sqs = :old_client
      new_sqs = :new_client

      described_class.sqs = old_sqs

      allow(Shoryuken::Queue).to receive(:new) do |client, _name|
        instance_double(Shoryuken::Queue, client: client)
      end

      # Widen the window between resetting the cache and installing the new client so a concurrent
      # `queues` call would cache a queue built with the old client unless the swap is atomic.
      allow(Shoryuken).to receive(:sqs_client=).and_wrap_original do |original, client|
        sleep 0.05
        original.call(client)
      end

      replacer = Thread.new { described_class.sqs = new_sqs }
      sleep 0.01
      reader = Thread.new { described_class.queues('concurrent') }
      [replacer, reader].each(&:join)

      expect(described_class.queues('concurrent').client).to eq(new_sqs)
    end
  end
end
