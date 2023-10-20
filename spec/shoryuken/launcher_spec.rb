require 'spec_helper'
require 'shoryuken/launcher'

RSpec.describe Shoryuken::Launcher do
  let(:executor) do
    # We can't use Concurrent.global_io_executor in these tests since once you
    # shut down a thread pool, you can't start it back up. Instead, we create
    # one new thread pool executor for each spec. We use a new
    # CachedThreadPool, since that most closely resembles
    # Concurrent.global_io_executor
    Concurrent::CachedThreadPool.new auto_terminate: true
  end

  let(:first_group_manager) { double(:first_group_manager, group: 'first_group') }
  let(:second_group_manager) { double(:second_group_manager, group: 'second_group') }
  let(:first_queue) { "launcher_spec_#{SecureRandom.uuid}" }
  let(:second_queue) { "launcher_spec_#{SecureRandom.uuid}" }

  before do
    Shoryuken.add_group('first_group', 1)
    Shoryuken.add_group('second_group', 1)
    Shoryuken.add_queue(first_queue, 1, 'first_group')
    Shoryuken.add_queue(second_queue, 1, 'second_group')
    allow(Shoryuken).to receive(:launcher_executor).and_return(executor)
    allow(Shoryuken::Manager).to receive(:new).with('first_group', any_args).and_return(first_group_manager)
    allow(Shoryuken::Manager).to receive(:new).with('second_group', any_args).and_return(second_group_manager)
    allow(first_group_manager).to receive(:running?).and_return(true)
    allow(second_group_manager).to receive(:running?).and_return(true)
  end

  describe '#healthy?' do
    context 'when all groups have managers' do
      context 'when all managers are running' do
        it 'returns true' do
          expect(subject.healthy?).to be true
        end
      end

      context 'when one manager is not running' do
        before do
          allow(second_group_manager).to receive(:running?).and_return(false)
        end

        it 'returns false' do
          expect(subject.healthy?).to be false
        end
      end
    end

    context 'when all groups do not have managers' do
      before do
        allow(second_group_manager).to receive(:group).and_return('some_random_group')
      end

      it 'returns false' do
        expect(subject.healthy?).to be false
      end
    end
  end

  describe '#stop' do
    before do
      allow(first_group_manager).to receive(:stop_new_dispatching)
      allow(first_group_manager).to receive(:await_dispatching_in_progress)
      allow(second_group_manager).to receive(:stop_new_dispatching)
      allow(second_group_manager).to receive(:await_dispatching_in_progress)
    end

    it 'fires quiet, shutdown and stopped event' do
      allow(subject).to receive(:fire_event)
      subject.stop
      expect(subject).to have_received(:fire_event).with(:quiet, true)
      expect(subject).to have_received(:fire_event).with(:shutdown, true)
      expect(subject).to have_received(:fire_event).with(:stopped)
    end

    it 'stops the managers' do
      subject.stop
      expect(first_group_manager).to have_received(:stop_new_dispatching)
      expect(second_group_manager).to have_received(:stop_new_dispatching)
    end
  end

  describe '#stop!' do
    before do
      allow(first_group_manager).to receive(:stop_new_dispatching)
      allow(first_group_manager).to receive(:await_dispatching_in_progress)
      allow(second_group_manager).to receive(:stop_new_dispatching)
      allow(second_group_manager).to receive(:await_dispatching_in_progress)
    end

    it 'fires shutdown and stopped event' do
      allow(subject).to receive(:fire_event)
      subject.stop!
      expect(subject).to have_received(:fire_event).with(:shutdown, true)
      expect(subject).to have_received(:fire_event).with(:stopped)
    end

    it 'stops the managers' do
      subject.stop!
      expect(first_group_manager).to have_received(:stop_new_dispatching)
      expect(second_group_manager).to have_received(:stop_new_dispatching)
    end
  end
end
