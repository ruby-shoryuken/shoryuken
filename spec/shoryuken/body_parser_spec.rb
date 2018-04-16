require 'spec_helper'
require 'shoryuken/body_parser'

RSpec.describe Shoryuken::BodyParser do
  let(:sqs_msg) { double }

  describe '#parser' do
    it 'parses the body into JSON' do
      TestWorker.get_shoryuken_options['body_parser'] = :json

      body = { 'test' => 'hi' }

      allow(sqs_msg).to receive(:body).and_return(JSON.dump(body))

      expect(described_class.parse(TestWorker, sqs_msg)).to eq(body)
    end

    it 'parses the body calling the proc' do
      TestWorker.get_shoryuken_options['body_parser'] = proc { |sqs_msg| "*#{sqs_msg.body}*" }

      allow(sqs_msg).to receive(:body).and_return('test')

      expect(described_class.parse(TestWorker, sqs_msg)).to eq('*test*')
    end

    it 'parses the body as text' do
      TestWorker.get_shoryuken_options['body_parser'] = :text

      body = 'test'

      allow(sqs_msg).to receive(:body).and_return(body)

      expect(described_class.parse(TestWorker, sqs_msg)).to eq('test')
    end

    it 'parses calling `.load`' do
      TestWorker.get_shoryuken_options['body_parser'] = Class.new do
        def self.load(*args)
          JSON.load(*args)
        end
      end

      body = { 'test' => 'hi' }

      allow(sqs_msg).to receive(:body).and_return(JSON.dump(body))

      expect(described_class.parse(TestWorker, sqs_msg)).to eq(body)
    end

    it 'parses calling `.parse`' do
      TestWorker.get_shoryuken_options['body_parser'] = Class.new do
        def self.parse(*args)
          JSON.parse(*args)
        end
      end

      body = { 'test' => 'hi' }

      allow(sqs_msg).to receive(:body).and_return(JSON.dump(body))

      expect(described_class.parse(TestWorker, sqs_msg)).to eq(body)
    end

    context 'when parse errors' do
      before do
        TestWorker.get_shoryuken_options['body_parser'] = :json

        allow(sqs_msg).to receive(:body).and_return('invalid JSON')
      end

      specify do
        expect { described_class.parse(TestWorker, sqs_msg) }
          .to raise_error(JSON::ParserError, /unexpected token at 'invalid JSON'/)
      end
    end

    context 'when `object_type: nil`' do
      it 'parses the body as text' do
        TestWorker.get_shoryuken_options['body_parser'] = nil

        body = 'test'

        allow(sqs_msg).to receive(:body).and_return(body)

        expect(described_class.parse(TestWorker, sqs_msg)).to eq(body)
      end
    end
  end
end
