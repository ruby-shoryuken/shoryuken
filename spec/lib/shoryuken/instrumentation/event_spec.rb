# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Instrumentation::Event do
  describe '#initialize' do
    it 'sets the name' do
      event = described_class.new('message.processed')
      expect(event.name).to eq('message.processed')
    end

    it 'sets the payload' do
      event = described_class.new('message.processed', queue: 'default', worker: 'TestWorker')
      expect(event.payload).to eq(queue: 'default', worker: 'TestWorker')
    end

    it 'defaults payload to empty hash' do
      event = described_class.new('message.processed')
      expect(event.payload).to eq({})
    end

    it 'sets the time' do
      freeze_time = Time.now
      allow(Time).to receive(:now).and_return(freeze_time)

      event = described_class.new('message.processed')
      expect(event.time).to eq(freeze_time)
    end
  end

  describe '#[]' do
    it 'returns payload value by key' do
      event = described_class.new('message.processed', queue: 'default')
      expect(event[:queue]).to eq('default')
    end

    it 'returns nil for missing key' do
      event = described_class.new('message.processed')
      expect(event[:missing]).to be_nil
    end
  end

  describe '#duration' do
    it 'returns duration from payload' do
      event = described_class.new('message.processed', duration: 1.5)
      expect(event.duration).to eq(1.5)
    end

    it 'returns nil if duration not set' do
      event = described_class.new('message.processed')
      expect(event.duration).to be_nil
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      freeze_time = Time.now
      allow(Time).to receive(:now).and_return(freeze_time)

      event = described_class.new('message.processed', queue: 'default')

      expect(event.to_h).to eq(
        name: 'message.processed',
        payload: { queue: 'default' },
        time: freeze_time
      )
    end
  end
end
