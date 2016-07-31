require 'spec_helper'
require 'shoryuken/manager'

RSpec.describe Shoryuken::Manager do
  let(:queue1) { 'shoryuken' }
  let(:queue2) { 'uppercut'}
  let(:queues) { [] }
  let(:polling_strategy) { Shoryuken::Polling::WeightedRoundRobin.new(queues) }
  let(:fetcher) { Shoryuken::Fetcher.new(manager, polling_strategy) }
  let(:condvar) do
    condvar = double(:condvar)
    allow(condvar).to receive(:signal).and_return(nil)
    condvar
  end
  let(:manager) { Shoryuken::Manager.new(condvar) }

  subject { manager }

  before(:each) do
    manager.fetcher = fetcher
  end

  describe 'Invalid concurrency setting' do
    it 'raises ArgumentError if concurrency is not positive number' do
      Shoryuken.options[:concurrency] = -1
      expect { Shoryuken::Manager.new(nil) }
        .to raise_error(ArgumentError, 'Concurrency value -1 is invalid, it needs to be a positive number')
    end
  end
end
