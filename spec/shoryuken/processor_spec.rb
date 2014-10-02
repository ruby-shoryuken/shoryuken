require 'spec_helper'

describe Shoryuken::Processor do
  let(:manager)   { double Shoryuken::Manager }
  let(:sqs_queue) { double 'Queue' }
  let(:queue)     { 'yo' }
  let(:sqs_msg)   { double AWS::SQS::ReceivedMessage, id: 'fc754df7-9cc2-4c41-96ca-5996a44b771e' }

  subject { described_class.new(manager) }

  before do
    allow(manager).to receive(:async).and_return(manager)
    allow(Shoryuken::Client).to receive(:queues).with(queue).and_return(sqs_queue)
  end

  describe '#process' do
    class YoWorker
      include Shoryuken::Worker

      shoryuken_options queue: 'yo'

      def perform(sqs_msg); end
    end

    it 'skips when worker not found' do
      queue = 'notfound'

      expect(manager).to receive(:processor_done).with(queue, subject)

      expect(sqs_msg).to_not receive(:delete)

      subject.process(queue, sqs_msg)
    end

    context 'when custom middleware' do
      class WorkerCalledMiddleware
        def call(worker, queue, sqs_msg)
          worker.called(sqs_msg, queue)
          yield
        end
      end

      before do
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

        expect_any_instance_of(YoWorker).to receive(:perform).with(sqs_msg)
        expect_any_instance_of(YoWorker).to receive(:called).with(sqs_msg, queue)

        subject.process(queue, sqs_msg)
      end
    end

    it 'performs with auto delete' do
      YoWorker.get_shoryuken_options['auto_delete'] = true

      expect(manager).to receive(:processor_done).with(queue, subject)

      expect_any_instance_of(YoWorker).to receive(:perform).with(sqs_msg)

      expect(sqs_msg).to receive(:delete)

      subject.process(queue, sqs_msg)
    end

    it 'performs without auto delete' do
      YoWorker.get_shoryuken_options['auto_delete'] = false

      expect(manager).to receive(:processor_done).with(queue, subject)

      expect_any_instance_of(YoWorker).to receive(:perform).with(sqs_msg)

      expect(sqs_msg).to_not receive(:delete)

      subject.process(queue, sqs_msg)
    end
  end
end
