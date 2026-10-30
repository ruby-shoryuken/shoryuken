# frozen_string_literal: true

RSpec.describe Shoryuken::Contracts::Worker do
  def errors(opts)
    described_class.new.call(opts).errors
  end

  it 'accepts every known worker option' do
    opts = %w[
      queue delete auto_delete auto_visibility_timeout retry_intervals batch body_parser non_retryable_exceptions
    ].to_h { |key| [key, nil] }

    expect(errors(opts)).to be_empty
  end

  it 'accepts Symbol keys' do
    expect(errors(queue: 'default', auto_delete: true)).to be_empty
  end

  it 'reports each unknown key' do
    expect(errors('queue' => 'default', 'auto_delte' => true, 'sqs' => {})).to eq(
      auto_delte: 'is not a known worker option',
      sqs: 'is not a known worker option'
    )
  end

  describe 'body_parser' do
    it 'accepts every handled form' do
      parse_only = Class.new do
        class << self
          def parse(body)
            body
          end
        end
      end

      load_only = Class.new do
        class << self
          def load(body)
            body
          end
        end
      end

      [nil, :json, :text, proc { |msg| msg }, ->(msg) { msg }, JSON, parse_only, load_only].each do |parser|
        expect(errors('body_parser' => parser)).to be_empty, "expected #{parser.inspect} to be accepted"
      end
    end

    it 'reports each unsupported value' do
      message = 'needs to be nil, :json, :text, a Proc or an object that responds to parse or load'

      [:JSON, 'json', :yaml, JSON.method(:parse), Object.new, 123].each do |parser|
        expect(errors('body_parser' => parser)).to eq({ body_parser: message }), "expected #{parser.inspect} to be rejected"
      end
    end
  end

  it 'prefixes the keys with the scope' do
    expect { described_class.new.validate!({ 'batchh' => true }, scope: ['MyWorker']) }
      .to raise_error(Shoryuken::Errors::InvalidConfigurationError, /MyWorker\.batchh/)
  end
end
