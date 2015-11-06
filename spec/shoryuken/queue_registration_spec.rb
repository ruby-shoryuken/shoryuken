require 'spec_helper'

RSpec.describe Shoryuken::QueueRegistration do
  describe "#register_queues!" do
    let(:queues) { ["queue", -> {"block_queue"}] }
    let(:unregistered_queue) { "somequeue" }
    let(:dummy_worker) { Class.new }

    before do
      dummy_worker.include Shoryuken::Worker
      allow(Shoryuken).to receive(:register_worker)
    end

    subject { described_class.new(dummy_worker).register_queues! queues }

    it "registers normal string queues" do
      expect(Shoryuken).to receive(:register_worker).
        with("queue", dummy_worker)
      subject
    end

    it "registers the result of a block queue" do
      expect(Shoryuken).to receive(:register_worker).
        with("block_queue", dummy_worker)
      subject
    end

    it "returns the queues that were registered" do
      expect(subject).to eql(["queue", "block_queue"])
    end
  end
end
