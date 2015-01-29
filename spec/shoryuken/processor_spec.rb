require 'spec_helper'
require 'shoryuken/processor'
require 'shoryuken/manager'

describe Shoryuken::Processor do
  let(:manager)   { double Shoryuken::Manager, processor_done: nil }
  let(:sqs_queue) { double AWS::SQS::Queue, visibility_timeout: 30 }
  let(:queue)     { 'default' }
  let(:sqs_msg)   { double AWS::SQS::ReceivedMessage, id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e', body: 'test', message_attributes: {} }

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
      TestWorker.get_shoryuken_options['body_parser'] = Proc.new { |sqs_msg| "*#{sqs_msg.body}*" }

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

    it 'parses calling `.parse`' do
      TestWorker.get_shoryuken_options['body_parser'] = JSON

      body = { 'test' => 'hi' }

      expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, body)

      allow(sqs_msg).to receive(:body).and_return(JSON.dump(body))

      subject.process(queue, sqs_msg)
    end

    context 'when parse errors' do
      it 'does not fail' do
        TestWorker.get_shoryuken_options['body_parser'] = :json

        expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, nil)

        allow(sqs_msg).to receive(:body).and_return('invalid json')

        expect(subject.logger).to receive(:error).with("Error parsing the message body: 757: unexpected token at 'invalid json'\nbody_parser: json\nsqs_msg.body: invalid json")

        subject.process(queue, sqs_msg)
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
          expect(manager).to receive(:processor_done).with(queue, subject)

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
          expect(manager).to receive(:processor_done).with(queue, subject)

          expect_any_instance_of(WorkerCalledMiddlewareWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)
          expect_any_instance_of(WorkerCalledMiddlewareWorker).to_not receive(:called).with(sqs_msg, queue)

          subject.process(queue, sqs_msg)
        end
      end
    end

    it 'performs with delete' do
      TestWorker.get_shoryuken_options['auto_delete'] = true

      expect(manager).to receive(:processor_done).with(queue, subject)

      expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)

      expect(sqs_queue).to receive(:batch_delete).with(sqs_msg)

      subject.process(queue, sqs_msg)
    end

    it 'performs without delete' do
      TestWorker.get_shoryuken_options['auto_delete'] = false

      expect(manager).to receive(:processor_done).with(queue, subject)

      expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)

      expect(sqs_queue).to_not receive(:batch_delete)

      subject.process(queue, sqs_msg)
    end

    context 'when shoryuken_class header' do
      let(:sqs_msg) { double AWS::SQS::ReceivedMessage, id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e', body: 'test', message_attributes: {
        'shoryuken_class' => {
          string_value: TestWorker.to_s,
          data_type: 'String'
        }
      } }

      it 'performs without delete' do
        Shoryuken.worker_registry.clear # unregister TestWorker

        expect(manager).to receive(:processor_done).with(queue, subject)

        expect_any_instance_of(TestWorker).to receive(:perform).with(sqs_msg, sqs_msg.body)

        expect(sqs_queue).to_not receive(:batch_delete)

        subject.process(queue, sqs_msg)
      end
    end
  end

  describe '#auto_visibility_timeout' do
    let(:heartbeat)          { sqs_queue.visibility_timeout - 5 }
    let(:visibility_timeout) { sqs_queue.visibility_timeout }

    before do
      TestWorker.get_shoryuken_options['auto_visibility_timeout'] = true

      allow(sqs_queue).to receive(:visibility_timeout).and_return(15)
    end

    context 'when the worker takes a long time', slow: true do
      it 'extends the message invisibility to prevent it from being dequeued concurrently' do
        TestWorker.get_shoryuken_options['body_parser'] = Proc.new do |sqs_msg|
          sleep visibility_timeout
          'test'
        end

        expect(sqs_msg).to receive(:visibility_timeout=).with(visibility_timeout).once
        expect(manager).to receive(:processor_done).with(queue, subject)

        allow(sqs_msg).to receive(:body).and_return('test')

        subject.process(queue, sqs_msg)
      end
    end

    context 'when the worker takes a short time' do
      it 'does not extend the message invisibility' do
        expect(sqs_msg).to receive(:visibility_timeout=).never
        expect(manager).to receive(:processor_done).with(queue, subject)

        allow(sqs_msg).to receive(:body).and_return('test')

        subject.process(queue, sqs_msg)
      end
    end

    context 'when the worker fails' do
      it 'does not extend the message invisibility' do
        expect(sqs_msg).to receive(:visibility_timeout=).never
        expect_any_instance_of(TestWorker).to receive(:perform).and_raise 'worker failed'
        expect { subject.process(queue, sqs_msg) }.to raise_error
      end
    end
  end
end
