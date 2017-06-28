require 'spec_helper'

module Shoryuken
  RSpec.describe Options do
    describe '.add_group' do
      before do
        Shoryuken.groups.clear
        Shoryuken.add_group('group1', 25)
        Shoryuken.add_group('group2', 25)
      end

      specify do
        described_class.add_queue('queue1', 1, 'group1')
        described_class.add_queue('queue2', 2, 'group2')

        expect(described_class.groups['group1'][:queues]).to eq(%w(queue1))
        expect(described_class.groups['group2'][:queues]).to eq(%w(queue2 queue2))
      end
    end

    describe '.sqs_client_receive_message_opts' do
      before do
        Shoryuken.sqs_client_receive_message_opts
      end

      specify do
        Shoryuken.sqs_client_receive_message_opts = { test: 1 }
        expect(Shoryuken.sqs_client_receive_message_opts).to eq('default' => { test: 1 })

        Shoryuken.sqs_client_receive_message_opts['my_group'] = { test: 2 }
        expect(Shoryuken.sqs_client_receive_message_opts).to eq('default' => { test: 1 }, 'my_group' => { test: 2 })
      end
    end
  end
end
