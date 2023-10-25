require 'active_job'
require 'shoryuken/extensions/active_job_extensions'
require 'active_support/testing/time_helpers'

# Stand-in for a job class specified by the user
class TestJob < ActiveJob::Base; end

# rubocop:disable Metrics/BlockLength
RSpec.shared_examples 'active_job_adapters' do
  include ActiveSupport::Testing::TimeHelpers

  let(:job_sqs_send_message_parameters) { {} }
  let(:job) do
    job = TestJob.new
    job.sqs_send_message_parameters = job_sqs_send_message_parameters
    job
  end
  let(:fifo) { false }
  let(:queue) { double 'Queue', fifo?: fifo }

  before do
    allow(Shoryuken::Client).to receive(:queues).with(job.queue_name).and_return(queue)
  end

  describe '#enqueue' do
    specify do
      expect(queue).to receive(:send_message) do |hash|
        expect(hash[:message_deduplication_id]).to_not be
        expect(hash[:message_attributes]['shoryuken_class'][:string_value]).to eq(described_class::JobWrapper.to_s)
        expect(hash[:message_attributes]['shoryuken_class'][:data_type]).to eq("String")
        expect(hash[:message_attributes].keys).to eq(['shoryuken_class'])
      end
      expect(Shoryuken).to receive(:register_worker).with(job.queue_name, described_class::JobWrapper)

      subject.enqueue(job)
    end

    it "should mutate the job's sqs_send_message_parameters reference to match those sent to the queue" do
      expect(queue).to receive(:send_message) do |options|
        expect(options).to be(job.sqs_send_message_parameters)
      end
      subject.enqueue(job)
    end

    context 'when fifo' do
      let(:fifo) { true }

      it 'does not include job_id in the deduplication_id' do
        freeze_time do
          expect(queue).to receive(:send_message) do |hash|
            message_deduplication_id = Digest::SHA256.hexdigest(JSON.dump(job.serialize.except('job_id')))

            expect(hash[:message_deduplication_id]).to eq(message_deduplication_id)
          end
          expect(Shoryuken).to receive(:register_worker).with(job.queue_name, described_class::JobWrapper)

          subject.enqueue(job)
        end
      end

      context 'with message_deduplication_id' do
        context 'when message_deduplication_id is specified in options' do
          it 'should enqueue a message with the deduplication_id specified in options' do
            expect(queue).to receive(:send_message) do |hash|
              expect(hash[:message_deduplication_id]).to eq('options-dedupe-id')
            end
            subject.enqueue(job, message_deduplication_id: 'options-dedupe-id')
          end
        end

        context 'when message_deduplication_id is specified on the job' do
          let(:job_sqs_send_message_parameters) { { message_deduplication_id: 'job-dedupe-id' } }

          it 'should enqueue a message with the deduplication_id specified on the job' do
            expect(queue).to receive(:send_message) do |hash|
              expect(hash[:message_deduplication_id]).to eq('job-dedupe-id')
            end
            subject.enqueue job
          end
        end

        context 'when message_deduplication_id is specified on the job and also in options' do
          let(:job_sqs_send_message_parameters) { { message_deduplication_id: 'job-dedupe-id' } }

          it 'should enqueue a message with the deduplication_id specified in options' do
            expect(queue).to receive(:send_message) do |hash|
              expect(hash[:message_deduplication_id]).to eq('options-dedupe-id')
            end
            subject.enqueue(job, message_deduplication_id: 'options-dedupe-id')
          end
        end
      end
    end

    context 'with message_group_id' do
      context 'when message_group_id is specified in options' do
        it 'should enqueue a message with the group_id specified in options' do
          expect(queue).to receive(:send_message) do |hash|
            expect(hash[:message_group_id]).to eq('options-group-id')
          end
          subject.enqueue(job, message_group_id: 'options-group-id')
        end
      end

      context 'when message_group_id is specified on the job' do
        let(:job_sqs_send_message_parameters) { { message_group_id: 'job-group-id' } }

        it 'should enqueue a message with the group_id specified on the job' do
          expect(queue).to receive(:send_message) do |hash|
            expect(hash[:message_group_id]).to eq('job-group-id')
          end
          subject.enqueue job
        end
      end

      context 'when message_group_id is specified on the job and also in options' do
        let(:job_sqs_send_message_parameters) { { message_group_id: 'job-group-id' } }

        it 'should enqueue a message with the group_id specified in options' do
          expect(queue).to receive(:send_message) do |hash|
            expect(hash[:message_group_id]).to eq('options-group-id')
          end
          subject.enqueue(job, message_group_id: 'options-group-id')
        end
      end
    end

    context 'with additional message attributes' do
      it 'should combine with activejob attributes' do
        custom_message_attributes = {
          'tracer_id' => {
            string_value: SecureRandom.hex,
            data_type: 'String'
          }
        }

        expect(queue).to receive(:send_message) do |hash|
          expect(hash[:message_attributes]['shoryuken_class'][:string_value]).to eq(described_class::JobWrapper.to_s)
          expect(hash[:message_attributes]['shoryuken_class'][:data_type]).to eq("String")
          expect(hash[:message_attributes]['tracer_id'][:string_value]).to eq(custom_message_attributes['tracer_id'][:string_value])
          expect(hash[:message_attributes]['tracer_id'][:data_type]).to eq("String")
        end
        expect(Shoryuken).to receive(:register_worker).with(job.queue_name, described_class::JobWrapper)

        subject.enqueue(job, message_attributes: custom_message_attributes)
      end

      context 'when message_attributes are specified on the job' do
        let(:job_sqs_send_message_parameters) do
          {
            message_attributes: {
              'tracer_id' => {
                data_type: 'String',
                string_value: 'job-value'
              }
            }
          }
        end

        it 'should enqueue a message with the message_attributes specified on the job' do
          expect(queue).to receive(:send_message) do |hash|
            expect(hash[:message_attributes]['tracer_id']).to eq({ data_type: 'String', string_value: 'job-value' })
            expect(hash[:message_attributes]['shoryuken_class']).to eq({ data_type: 'String', string_value: described_class::JobWrapper.to_s })
          end
          subject.enqueue job
        end
      end

      context 'when message_attributes are specified on the job and also in options' do
        let(:job_sqs_send_message_parameters) do
          {
            message_attributes: {
              'tracer_id' => {
                data_type: 'String',
                string_value: 'job-value'
              }
            }
          }
        end

        it 'should enqueue a message with the message_attributes speficied in options' do
          custom_message_attributes = {
            'options_tracer_id' => {
              string_value: 'options-value',
              data_type: 'String'
            }
          }

          expect(queue).to receive(:send_message) do |hash|
            expect(hash[:message_attributes]['tracer_id']).to be_nil
            expect(hash[:message_attributes]['options_tracer_id']).to eq({ data_type: 'String', string_value: 'options-value' })
            expect(hash[:message_attributes]['shoryuken_class']).to eq({ data_type: 'String', string_value: described_class::JobWrapper.to_s })
          end
          subject.enqueue job, message_attributes: custom_message_attributes
        end
      end
    end
  end

  context 'with message_system_attributes' do
    context 'when message_system_attributes are specified in options' do
      it 'should enqueue a message with message_system_attributes specified in options' do
        system_attributes = {
          'AWSTraceHeader' => {
            string_value: 'trace_id',
            data_type: 'String'
          }
        }
        expect(queue).to receive(:send_message) do |hash|
          expect(hash[:message_system_attributes]['AWSTraceHeader'][:string_value]).to eq('trace_id')
          expect(hash[:message_system_attributes]['AWSTraceHeader'][:data_type]).to eq('String')
        end
        subject.enqueue(job, message_system_attributes: system_attributes)
      end
    end

    context 'when message_system_attributes are specified on the job' do
      let(:job_sqs_send_message_parameters) do
        {
          message_system_attributes: {
            'AWSTraceHeader' => {
              string_value: 'job-value',
              data_type: 'String'
            }
          }
        }
      end

      it 'should enqueue a message with the message_system_attributes specified on the job' do
        expect(queue).to receive(:send_message) do |hash|
          expect(hash[:message_system_attributes]['AWSTraceHeader']).to eq({ data_type: 'String', string_value: 'job-value' })
        end
        subject.enqueue job
      end
    end

    context 'when message_system_attributes are specified on the job and also in options' do
      let(:job_sqs_send_message_parameters) do
        {
          message_system_attributes: {
            'job_trace_header' => {
              string_value: 'job-value',
              data_type: 'String'
            }
          }
        }
      end

      it 'should enqueue a message with the message_system_attributes speficied in options' do
        custom_message_attributes = {
          'options_trace_header' => {
            string_value: 'options-value',
            data_type: 'String'
          }
        }

        expect(queue).to receive(:send_message) do |hash|
          expect(hash[:message_system_attributes]['job_trace_header']).to be_nil
          expect(hash[:message_system_attributes]['options_trace_header']).to eq({ data_type: 'String', string_value: 'options-value' })
        end
        subject.enqueue job, message_system_attributes: custom_message_attributes
      end
    end
  end

  describe '#enqueue_at' do
    specify do
      delay = 1

      expect(queue).to receive(:send_message) do |hash|
        expect(hash[:message_deduplication_id]).to_not be
        expect(hash[:delay_seconds]).to eq(delay)
      end

      expect(Shoryuken).to receive(:register_worker).with(job.queue_name, described_class::JobWrapper)

      # need to figure out what to require Time.current and N.minutes to remove the stub
      allow(subject).to receive(:calculate_delay).and_return(delay)

      subject.enqueue_at(job, nil)
    end
  end
end
# rubocop:enable Metrics/BlockLength
