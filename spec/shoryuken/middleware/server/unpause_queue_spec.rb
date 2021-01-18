require 'spec_helper'

describe Shoryuken::Middleware::Server::UnpauseQueue do
  let(:queue)             { 'default' }
  let(:queues)            { [queue] }
  let(:weighted_strategy) { Shoryuken::Polling::WeightedRoundRobin.new(queues) }
  let(:strict_strategy)   { Shoryuken::Polling::StrictPriority.new(queues) }
  let(:sqs_queue)         { double Shoryuken::Queue }

  def build_message
    double Shoryuken::Message,
           queue_url: queue,
           body: 'test',
           receipt_handle: SecureRandom.uuid
  end

  let(:sqs_msg) { build_message }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  context 'when strict strategy' do
    it 'unpauses fifo queue' do
      expect(sqs_queue).to receive(:fifo?).and_return(true)
      strict_strategy.send(:pause, queue)
      expect(strict_strategy.active_queues).to eq([])
      subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body, strict_strategy) {}
      expect(strict_strategy.active_queues).to eq([[queue, 1]])
    end

    it 'will not unpause non fifo queue' do
      expect(sqs_queue).to receive(:fifo?).and_return(false)
      strict_strategy.send(:pause, queue)
      expect(strict_strategy.active_queues).to eq([])
      subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body, strict_strategy) {}
      expect(strict_strategy.active_queues).to eq([])
    end
  end

  context 'when weighted strategy' do
    it 'unpauses fifo queue' do
      expect(sqs_queue).to receive(:fifo?).and_return(true)
      weighted_strategy.send(:pause, queue)
      expect(weighted_strategy.active_queues).to eq([])
      subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body, weighted_strategy) {}
      expect(weighted_strategy.active_queues).to eq([[queue, 1]])
    end

    it 'will not unpause non fifo queue' do
      expect(sqs_queue).to receive(:fifo?).and_return(false)
      weighted_strategy.send(:pause, queue)
      expect(weighted_strategy.active_queues).to eq([])
      subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body, weighted_strategy) {}
      expect(weighted_strategy.active_queues).to eq([])
    end
  end
end
