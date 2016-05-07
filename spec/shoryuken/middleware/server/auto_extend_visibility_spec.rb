require 'spec_helper'

describe Shoryuken::Middleware::Server::AutoExtendVisibility do
  let(:queue) { 'default' }
  let(:visibility_timeout) { 3 }
  let(:extend_upfront) { 1 }
  let(:sqs_queue) { instance_double Shoryuken::Queue, visibility_timeout: visibility_timeout }

  def build_message
    double Shoryuken::Message, queue_url: queue, body: 'test', receipt_handle: SecureRandom.uuid
  end

  # We need to run our worker inside actor context.
  class Runner
    include Celluloid

    def run(worker, queue, sqs_msg)
      Shoryuken::Middleware::Server::AutoExtendVisibility.new.call(worker, queue, sqs_msg, sqs_msg.body) {}
    end
  end

  let(:sqs_msg) { build_message }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
    stub_const('Shoryuken::Middleware::Server::AutoExtendVisibility::EXTEND_UPFRONT_SECONDS', extend_upfront)
  end

  it 'extends message visibility' do
    TestWorker.get_shoryuken_options['auto_visibility_timeout'] = true

    allow(sqs_msg).to receive(:queue) { sqs_queue }
    expect(sqs_msg).to receive(:change_visibility).with(visibility_timeout: visibility_timeout)
    expect_any_instance_of(Celluloid).to receive(:every).
      with(visibility_timeout - extend_upfront).
      once { |_, _, &block| block.call }

    Runner.new.run(TestWorker.new, queue, sqs_msg)
  end

  it 'does not extend message visibility if auto_visibility_timeout is not true' do
    TestWorker.get_shoryuken_options['auto_visibility_timeout'] = false

    allow(sqs_msg).to receive(:queue) { sqs_queue }
    expect(sqs_msg).to_not receive(:change_visibility)
    expect_any_instance_of(Celluloid).to_not receive(:every)

    Runner.new.run(TestWorker.new, queue, sqs_msg)
  end
end
