# frozen_string_literal: true

RSpec.describe Shoryuken::Middleware::Server::AutoExtendVisibility do
  let(:queue) { 'default' }
  let(:visibility_timeout) { 3 }
  let(:extend_upfront) { 1 }
  let(:sqs_queue) { instance_double Shoryuken::Queue, visibility_timeout: visibility_timeout }

  def build_message
    double Shoryuken::Message, queue_url: queue, body: 'test', receipt_handle: SecureRandom.uuid
  end

  # We need to run our worker inside actor context.
  class Runner
    def run_and_sleep(worker, queue, sqs_msg, interval)
      Shoryuken::Middleware::Server::AutoExtendVisibility.new.call(worker, queue, sqs_msg, sqs_msg.body) do
        sleep interval
      end
    end

    def run_and_raise(worker, queue, sqs_msg)
      Shoryuken::Middleware::Server::AutoExtendVisibility.new.call(worker, queue, sqs_msg, sqs_msg.body) do
        raise
      end
    end
  end

  let(:sqs_msg) { build_message }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
    stub_const('Shoryuken::Middleware::Server::AutoExtendVisibility::EXTEND_UPFRONT_SECONDS', extend_upfront)
  end

  context 'when batch worker' do
    it 'yields' do
      expect { |b| subject.call(TestWorker.new, nil, [], nil, &b) }.to yield_control
    end
  end

  it 'extends message visibility if jobs takes a long time' do
    TestWorker.get_shoryuken_options['auto_visibility_timeout'] = true

    allow(sqs_msg).to receive(:queue) { sqs_queue }
    expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: visibility_timeout)

    Runner.new.run_and_sleep(TestWorker.new, queue, sqs_msg, visibility_timeout)
  end

  it 'does not extend message visibility if worker raises' do
    TestWorker.get_shoryuken_options['auto_visibility_timeout'] = true

    allow(sqs_msg).to receive(:queue) { sqs_queue }
    expect(sqs_msg).to_not receive(:change_visibility)

    expect { Runner.new.run_and_raise(TestWorker.new, queue, sqs_msg) }.to raise_error(RuntimeError)
  end

  it 'does not extend message visibility if auto_visibility_timeout is not true' do
    TestWorker.get_shoryuken_options['auto_visibility_timeout'] = false

    allow(sqs_msg).to receive(:queue) { sqs_queue }
    expect(sqs_msg).to_not receive(:change_visibility)

    Runner.new.run_and_sleep(TestWorker.new, queue, sqs_msg, visibility_timeout)
  end

  context 'when batch worker with auto_visibility_timeout' do
    it 'warns and does not extend visibility for batch workers' do
      TestWorker.get_shoryuken_options['auto_visibility_timeout'] = true

      expect(Shoryuken.logger).to receive(:warn) do |&block|
        expect(block.call).to include("Auto extend visibility isn't supported for batch workers")
      end

      expect { |b| subject.call(TestWorker.new, queue, [sqs_msg], nil, &b) }.to yield_control
    end
  end

  context 'with a receive-time visibility_timeout' do
    let(:receive_visibility_timeout) { 2 }

    before do
      TestWorker.get_shoryuken_options['auto_visibility_timeout'] = true
      allow(sqs_msg).to receive(:message_id).and_return('test-message-id')
    end

    it 'extends by the visibility_timeout set for the queue, before it expires' do
      Shoryuken.sqs_client_receive_message_opts[queue] = { visibility_timeout: receive_visibility_timeout }

      expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: receive_visibility_timeout)

      Runner.new.run_and_sleep(TestWorker.new, queue, sqs_msg, 1.5)
    end

    it 'extends by the visibility_timeout set for the group of the queue' do
      Shoryuken.add_group('custom', 1)
      Shoryuken.add_queue(queue, 1, 'custom')
      Shoryuken.sqs_client_receive_message_opts['custom'] = { visibility_timeout: receive_visibility_timeout }

      expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: receive_visibility_timeout)

      Runner.new.run_and_sleep(TestWorker.new, queue, sqs_msg, 1.5)
    end

    it 'uses the queue visibility timeout when the receive options do not set one' do
      Shoryuken.sqs_client_receive_message_opts[queue] = { wait_time_seconds: 1 }

      expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: visibility_timeout)

      Runner.new.run_and_sleep(TestWorker.new, queue, sqs_msg, visibility_timeout)
    end
  end

  context 'when visibility extension fails' do
    it 'logs error when change_visibility raises an exception' do
      TestWorker.get_shoryuken_options['auto_visibility_timeout'] = true

      allow(sqs_msg).to receive(:queue) { sqs_queue }
      allow(sqs_msg).to receive(:message_id).and_return('test-message-id')
      allow(sqs_msg).to receive(:change_visibility).and_raise(StandardError, 'AWS error')

      expect(Shoryuken.logger).to receive(:error) do |&block|
        msg = block.call
        expect(msg).to include('Could not auto extend the message')
        expect(msg).to include('test-message-id')
        expect(msg).to include('AWS error')
      end

      Runner.new.run_and_sleep(TestWorker.new, queue, sqs_msg, visibility_timeout)
    end
  end

  context 'debug logging' do
    it 'logs debug message when extending visibility' do
      TestWorker.get_shoryuken_options['auto_visibility_timeout'] = true

      allow(sqs_msg).to receive(:queue) { sqs_queue }
      allow(sqs_msg).to receive(:message_id).and_return('test-message-id')
      allow(sqs_msg).to receive(:change_visibility)

      expect(Shoryuken.logger).to receive(:debug) do |&block|
        msg = block.call
        expect(msg).to include('Extending message')
        expect(msg).to include('test-message-id')
        expect(msg).to include("by #{visibility_timeout}s")
      end

      Runner.new.run_and_sleep(TestWorker.new, queue, sqs_msg, visibility_timeout)
    end
  end

  context 'when the visibility timeout is too short for the upfront margin' do
    # interval would be visibility_timeout - extend_upfront == 0, which used to
    # make TimerTask raise before the worker ran.
    let(:visibility_timeout) { extend_upfront }

    it 'runs the worker instead of raising' do
      TestWorker.get_shoryuken_options['auto_visibility_timeout'] = true
      allow(sqs_msg).to receive(:queue) { sqs_queue }
      allow(sqs_msg).to receive(:message_id).and_return('test-message-id')
      allow(sqs_msg).to receive(:change_visibility)

      ran = false
      subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { ran = true }

      expect(ran).to be true
    end
  end

  context 'when the visibility timeout is zero' do
    let(:visibility_timeout) { 0 }

    it 'warns and runs the worker without scheduling an extension' do
      TestWorker.get_shoryuken_options['auto_visibility_timeout'] = true
      allow(sqs_msg).to receive(:queue) { sqs_queue }
      allow(sqs_msg).to receive(:message_id).and_return('test-message-id')
      expect(sqs_msg).not_to receive(:change_visibility)
      expect(Shoryuken.logger).to receive(:warn)

      ran = false
      subject.call(TestWorker.new, queue, sqs_msg, sqs_msg.body) { ran = true }

      expect(ran).to be true
    end
  end
end
