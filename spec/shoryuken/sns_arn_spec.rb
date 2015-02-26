require 'spec_helper'

describe Shoryuken::SnsArn do
  let(:account_id) { '1234567890' }
  let(:region) { 'eu-west-1' }
  let(:topic) { 'topic-x' }

  before do
    Shoryuken::Client.account_id = account_id
    Aws.config = { region: region }
  end

  subject { described_class.new(topic).to_s }

  describe '#to_s' do
    context 'when the Aws config includes all the information necessary' do
      it 'generates an SNS arn' do
        expect(subject).to eq('arn:aws:sns:eu-west-1:1234567890:topic-x')
      end
    end

    context 'when the Aws config does not include the account id' do
      before do
        Shoryuken::Client.account_id = nil
      end

      it 'fails' do
        expect { subject }.to raise_error(/an :account_id/)
      end
    end

    context 'when the Aws config does not include the region' do
      before do
        Aws.config.delete :region
      end

      it 'fails' do
        expect { subject }.to raise_error(/a :region/)
      end
    end
  end
end
