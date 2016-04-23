require 'spec_helper'

describe Shoryuken::Middleware::Server::AutoExtendVisibility do
  let(:queue)     { 'default' }
  let(:visibility_timeout) { 3 }
  let(:extend_upfront) { 1 }
  let(:sqs_queue) { instance_double Shoryuken::Queue, visibility_timeout: visibility_timeout }

  def build_message
    double Shoryuken::Message,
      queue_url: queue,
      body: 'test',
      receipt_handle: SecureRandom.uuid
  end

  # We need to run our worker inside actor context.
  class Runner
    include Celluloid

    def run_and_sleep(worker, queue, sqs_msg, sleep_interval)
      Shoryuken::Middleware::Server::AutoExtendVisibility.new.call(worker, queue, sqs_msg, sqs_msg.body) do
        sleep(sleep_interval)
      end
    end
  end

  let(:sqs_msg) { build_message }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
    stub_const('Shoryuken::Middleware::Server::AutoExtendVisibility::EXTEND_UPFRONT_SECONDS', extend_upfront)
  end

  it 'extends message visibility if processing is taking long enough' do
    TestWorker.get_shoryuken_options['auto_visibility_timeout'] = true

    allow(sqs_msg).to receive(:queue){ sqs_queue }
    expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: visibility_timeout)

    Runner.new.run_and_sleep(TestWorker.new, queue, sqs_msg, visibility_timeout)
  end

  it 'does not extend message visibility if processing finishes before timeout - extend_upfront' do
    TestWorker.get_shoryuken_options['auto_visibility_timeout'] = true

    allow(sqs_msg).to receive(:queue){ sqs_queue }
    expect(sqs_msg).to_not receive(:change_visibility)

    Runner.new.run_and_sleep(TestWorker.new, queue, sqs_msg, 1)
  end

  it 'does not extend message visibility if auto_visibility_timeout is not true' do
    TestWorker.get_shoryuken_options['auto_visibility_timeout'] = false

    allow(sqs_msg).to receive(:queue){ sqs_queue }
    expect(sqs_msg).to_not receive(:change_visibility)

    Runner.new.run_and_sleep(TestWorker.new, queue, sqs_msg, visibility_timeout)
  end
end
