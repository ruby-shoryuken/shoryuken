require 'spec_helper'

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

    def run_and_raise(worker, queue, sqs_msg, error_class)
      Shoryuken::Middleware::Server::AutoExtendVisibility.new.call(worker, queue, sqs_msg, sqs_msg.body) do
        raise error_class.new
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
      expect { |b| subject.call(nil, nil, [], nil, &b) }.to yield_control
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

    expect { Runner.new.run_and_raise(TestWorker.new, queue, sqs_msg, StandardError) }.to raise_error(StandardError)
  end

  it 'does not extend message visibility if auto_visibility_timeout is not true' do
    TestWorker.get_shoryuken_options['auto_visibility_timeout'] = false

    allow(sqs_msg).to receive(:queue) { sqs_queue }
    expect(sqs_msg).to_not receive(:change_visibility)

    Runner.new.run_and_sleep(TestWorker.new, queue, sqs_msg, visibility_timeout)
  end
end
