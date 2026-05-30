# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Shoryuken.monitor' do
  after do
    Shoryuken.reset_monitor!
  end

  describe '.monitor' do
    it 'returns a Notifications instance' do
      expect(Shoryuken.monitor).to be_a(Shoryuken::Instrumentation::Notifications)
    end

    it 'returns the same instance on multiple calls' do
      monitor1 = Shoryuken.monitor
      monitor2 = Shoryuken.monitor
      expect(monitor1).to be(monitor2)
    end

    it 'allows subscribing to events' do
      events = []
      Shoryuken.monitor.subscribe('test.event') { |e| events << e }

      Shoryuken.monitor.publish('test.event', key: 'value')

      expect(events.size).to eq(1)
      expect(events.first[:key]).to eq('value')
    end
  end

  describe '.reset_monitor!' do
    it 'creates a new monitor instance' do
      original = Shoryuken.monitor
      Shoryuken.reset_monitor!
      expect(Shoryuken.monitor).not_to be(original)
    end

    it 'clears subscribers' do
      events = []
      Shoryuken.monitor.subscribe('test.event') { |e| events << e }

      Shoryuken.reset_monitor!
      Shoryuken.monitor.publish('test.event')

      expect(events).to be_empty
    end
  end
end
