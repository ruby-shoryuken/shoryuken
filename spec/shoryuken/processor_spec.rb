require 'spec_helper'
require 'shoryuken/processor'
require 'shoryuken/manager'

RSpec.describe Shoryuken::Processor do
  let(:manager)   { double Shoryuken::Manager, processor_done: nil }
  let(:sqs_queue) { double Shoryuken::Queue, visibility_timeout: 30 }
  let(:queue)     { 'default' }

  let(:sqs_msg) do
    double Shoryuken::Message,
      queue_url: queue,
      body: 'test',
      message_attributes: {},
      message_id: SecureRandom.uuid,
      receipt_handle: SecureRandom.uuid
  end

  subject { described_class.new(manager) }

  before do
    allow(manager).to receive(:async).and_return(manager)
    allow(manager).to receive(:real_thread)
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  describe '#process' do
    it 'parses the body into JSON' do
      TestWorker.get_shoryuken_options['body_parser'] = :json

      body = { 'test' => 'hi' }

      expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, body)

      allow(sqs_msg).to receive(:body).and_return(JSON.dump(body))

      subject.process(queue, sqs_msg)
    end

    it 'parses the body calling the proc' do
      TestWorker.get_shoryuken_options['body_parser'] = proc { |sqs_msg| "*#{sqs_msg.body}*" }

      expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, '*test*')

      allow(sqs_msg).to receive(:body).and_return('test')

      subject.process(queue, sqs_msg)
    end

    it 'parses the body as text' do
      TestWorker.get_shoryuken_options['body_parser'] = :text

      body = 'test'

      expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, body)

      allow(sqs_msg).to receive(:body).and_return(body)

      subject.process(queue, sqs_msg)
    end

    it 'parses calling `.load`' do
      TestWorker.get_shoryuken_options['body_parser'] = Class.new do
        def self.load(*args)
          JSON.load(*args)
        end
      end

      body = { 'test' => 'hi' }

      expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, body)

      allow(sqs_msg).to receive(:body).and_return(JSON.dump(body))

      subject.process(queue, sqs_msg)
    end

    it 'parses calling `.parse`' do
      TestWorker.get_shoryuken_options['body_parser'] = Class.new do
        def self.parse(*args)
          JSON.parse(*args)
        end
      end

      body = { 'test' => 'hi' }

      expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, body)

      allow(sqs_msg).to receive(:body).and_return(JSON.dump(body))

      subject.process(queue, sqs_msg)
    end

    context 'when parse errors' do
      before do
        TestWorker.get_shoryuken_options['body_parser'] = :json

        allow(sqs_msg).to receive(:body).and_return('invalid json')
      end

      it 'logs the error' do
        expect(subject.logger).to receive(:error) do |&block|
          expect(block.call).
            to include("unexpected token at 'invalid json'\nbody_parser: json\nsqs_msg.body: invalid json")
        end

        subject.process(queue, sqs_msg) rescue nil
      end

      it 're raises the error' do
        expect { subject.process(queue, sqs_msg) }.
          to raise_error(JSON::ParserError, /unexpected token at 'invalid json'/)
      end
    end

    context 'when `object_type: nil`' do
      it 'parses the body as text' do
        TestWorker.get_shoryuken_options['body_parser'] = nil

        body = 'test'

        expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, body)

        allow(sqs_msg).to receive(:body).and_return(body)

        subject.process(queue, sqs_msg)
      end
    end

    context 'when custom middleware' do
      let(:queue) { 'worker_called_middleware' }

      class WorkerCalledMiddleware
        def call(worker, queue, sqs_msg, body)
          # called is defined with `allow(...).to receive(...)`
          worker.called(sqs_msg, queue)
          yield
        end
      end

      before do
        class WorkerCalledMiddlewareWorker
          include Shoryuken::Worker

          shoryuken_options queue: 'worker_called_middleware'

          def perform(sqs_msg, body); end
        end
      end

      context 'server' do
        before do
          allow(Shoryuken).to receive(:server?).and_return(true)
          WorkerCalledMiddlewareWorker.instance_variable_set(:@server_chain, nil) # un-memoize middleware

          Shoryuken.configure_server do |config|
            config.server_middleware do |chain|
              chain.add WorkerCalledMiddleware
            end
          end
        end

        after do
          Shoryuken.configure_server do |config|
            config.server_middleware do |chain|
              chain.remove WorkerCalledMiddleware
            end
          end
        end

        it 'invokes middleware' do
          expect(manager).to receive(:processor_done).with(queue)

          expect_any_instance_of(WorkerCalledMiddlewareWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)
          expect_any_instance_of(WorkerCalledMiddlewareWorker).to receive(:called).with(sqs_msg, queue)

          subject.process(queue, sqs_msg)
        end
      end

      context 'client' do
        before do
          allow(Shoryuken).to receive(:server?).and_return(false)
          WorkerCalledMiddlewareWorker.instance_variable_set(:@server_chain, nil) # un-memoize middleware

          Shoryuken.configure_server do |config|
            config.server_middleware do |chain|
              chain.add WorkerCalledMiddleware
            end
          end
        end

        after do
          Shoryuken.configure_server do |config|
            config.server_middleware do |chain|
              chain.remove WorkerCalledMiddleware
            end
          end
        end

        it "doesn't invoke middleware" do
          expect(manager).to receive(:processor_done).with(queue)

          expect_any_instance_of(WorkerCalledMiddlewareWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)
          expect_any_instance_of(WorkerCalledMiddlewareWorker).to_not receive(:called).with(sqs_msg, queue)

          subject.process(queue, sqs_msg)
        end
      end
    end

    it 'performs with delete' do
      TestWorker.get_shoryuken_options['auto_delete'] = true

      expect(manager).to receive(:processor_done).with(queue)

      expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)

      expect(sqs_queue).to receive(:delete_messages).with(entries: [{ id: '0', receipt_handle: sqs_msg.receipt_handle }])

      subject.process(queue, sqs_msg)
    end

    it 'performs without delete' do
      TestWorker.get_shoryuken_options['auto_delete'] = false

      expect(manager).to receive(:processor_done).with(queue)

      expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)

      expect(sqs_queue).to_not receive(:delete_messages)

      subject.process(queue, sqs_msg)
    end

    context 'when shoryuken_class header' do
      let(:sqs_msg) do
        double Shoryuken::Message,
          queue_url: queue,
          body: 'test',
          message_attributes: {
            'shoryuken_class' => {
              string_value: TestWorker.to_s,
              data_type: 'String' }},
              message_id: SecureRandom.uuid,
              receipt_handle: SecureRandom.uuid
      end

      it 'performs without delete' do
        Shoryuken.worker_registry.clear # unregister TestWorker

        expect(manager).to receive(:processor_done).with(queue)

        expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)

        expect(sqs_queue).to_not receive(:delete_messages)

        subject.process(queue, sqs_msg)
      end
    end
  end
end
