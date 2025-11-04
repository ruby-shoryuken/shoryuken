# frozen_string_literal: true

require 'spec_helper'

# Skip this spec if ActiveSupport is not available, as the extensions require it
if defined?(ActiveSupport)
  require 'active_job/extensions'

  RSpec.describe Shoryuken::ActiveJob do
    describe Shoryuken::ActiveJob::SQSSendMessageParametersAccessor do
      let(:job_class) do
        Class.new do
          include Shoryuken::ActiveJob::SQSSendMessageParametersAccessor
        end
      end

      let(:job_instance) { job_class.new }

      describe 'included behavior' do
        it 'adds sqs_send_message_parameters accessor' do
          expect(job_instance).to respond_to(:sqs_send_message_parameters)
          expect(job_instance).to respond_to(:sqs_send_message_parameters=)
        end

        it 'allows setting and getting sqs_send_message_parameters' do
          params = { message_group_id: 'group1', message_deduplication_id: 'dedup1' }
          job_instance.sqs_send_message_parameters = params
          expect(job_instance.sqs_send_message_parameters).to eq(params)
        end
      end
    end

    describe Shoryuken::ActiveJob::SQSSendMessageParametersSupport do
      let(:base_class) do
        Class.new do
          attr_accessor :sqs_send_message_parameters

          def initialize(*arguments)
            # Mock ActiveJob::Base initialization
          end

          def enqueue(options = {})
            # Mock ActiveJob::Base enqueue method that returns remaining options
            options
          end
        end
      end

      let(:job_class) do
        Class.new(base_class) do
          prepend Shoryuken::ActiveJob::SQSSendMessageParametersSupport
        end
      end

      describe '#initialize' do
        it 'initializes sqs_send_message_parameters to empty hash' do
          job = job_class.new('arg1', 'arg2')
          expect(job.sqs_send_message_parameters).to eq({})
        end

        it 'calls super with the provided arguments' do
          expect_any_instance_of(base_class).to receive(:initialize).with('arg1', 'arg2')
          job_class.new('arg1', 'arg2')
        end

        it 'handles ruby2_keywords compatibility' do
          # Test that ruby2_keywords is called if available
          if respond_to?(:ruby2_keywords, true)
            expect(job_class.method(:new)).to respond_to(:ruby2_keywords) if RUBY_VERSION >= '2.7'
          end
        end
      end

      describe '#enqueue' do
        let(:job_instance) { job_class.new }

        it 'extracts SQS-specific options and merges them into sqs_send_message_parameters' do
          options = {
            wait: 5 * 60, # 5 minutes in seconds
            message_attributes: { 'type' => 'important' },
            message_system_attributes: { 'source' => 'api' },
            message_deduplication_id: 'dedup123',
            message_group_id: 'group456',
            other_option: 'value'
          }

          remaining_options = job_instance.enqueue(options)

          expect(job_instance.sqs_send_message_parameters).to eq({
            message_attributes: { 'type' => 'important' },
            message_system_attributes: { 'source' => 'api' },
            message_deduplication_id: 'dedup123',
            message_group_id: 'group456'
          })

          expect(remaining_options).to eq({
            wait: 300,
            other_option: 'value'
          })
        end

        it 'handles empty options gracefully' do
          remaining_options = job_instance.enqueue({})
          expect(job_instance.sqs_send_message_parameters).to eq({})
          expect(remaining_options).to eq({})
        end

        it 'merges new SQS options with existing ones' do
          job_instance.sqs_send_message_parameters = { message_group_id: 'existing_group' }

          options = { message_deduplication_id: 'new_dedup' }
          job_instance.enqueue(options)

          expect(job_instance.sqs_send_message_parameters).to eq({
            message_group_id: 'existing_group',
            message_deduplication_id: 'new_dedup'
          })
        end

        it 'overwrites existing SQS options when the same key is provided' do
          job_instance.sqs_send_message_parameters = { message_group_id: 'old_group' }

          options = { message_group_id: 'new_group' }
          job_instance.enqueue(options)

          expect(job_instance.sqs_send_message_parameters).to eq({
            message_group_id: 'new_group'
          })
        end
      end
    end

    describe 'module constants' do
      it 'defines SQSSendMessageParametersAccessor' do
        expect(Shoryuken::ActiveJob::SQSSendMessageParametersAccessor).to be_a(Module)
      end

      it 'defines SQSSendMessageParametersSupport' do
        expect(Shoryuken::ActiveJob::SQSSendMessageParametersSupport).to be_a(Module)
      end
    end
  end
else
  RSpec.describe 'Shoryuken::ActiveJob (skipped - ActiveSupport not available)' do
    it 'skips tests when ActiveSupport is not available' do
      skip('ActiveSupport not available in test environment')
    end
  end
end