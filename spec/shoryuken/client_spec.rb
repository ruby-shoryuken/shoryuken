require 'spec_helper'

describe Shoryuken::Client do
  let(:credentials) { Aws::Credentials.new('access_key_id', 'secret_access_key') }
  let(:sqs)         { Aws::SQS::Client.new(stub_responses: true, credentials: credentials) }
  let(:queue_name)  { 'shoryuken' }
  let(:queue_url)   { 'https://eu-west-1.amazonaws.com:6059/123456789012/shoryuken' }
  let(:sqs_endpoint) { 'http://localhost:4568' }
  let(:sns_endpoint) { 'http://0.0.0.0:4568'   }

  describe '.queue' do
    before do
      described_class.sqs = sqs
    end
    it 'memoizes queues' do
      sqs.stub_responses(:get_queue_url, { queue_url: queue_url }, { queue_url: 'xyz' })

      expect(Shoryuken::Client.queues(queue_name).url).to eq queue_url
      expect(Shoryuken::Client.queues(queue_name).url).to eq queue_url
    end
  end

  describe 'environment variable endpoints' do
    before do
      ENV['AWS_SQS_ENDPOINT'] = sqs_endpoint
      ENV['AWS_SNS_ENDPOINT'] = sns_endpoint
      ENV['AWS_REGION'] = 'us-east-1'
      Shoryuken.options[:aws] = {}
      Shoryuken::AwsConfig.options = {}
    end

    it 'will use config file settings if set' do
      load_config_file_by_file_name('shoryuken_endpoint.yml')
      expect(described_class.sqs.config.endpoint.to_s).to eql('https://github.com/phstc/shoryuken:4568')
      expect(described_class.sns.config.endpoint.to_s).to eq('http://127.0.0.1:4568')
    end

    it 'should fallback to environment variable if config file not found or set' do
      load_config_file_by_file_name(nil)
      expect(described_class.sqs.config.endpoint.to_s).to eql(sqs_endpoint)
      expect(described_class.sns.config.endpoint.to_s).to eq(sns_endpoint)
    end

    it 'should fallback to environment variable if config file found but settings not set' do
      load_config_file_by_file_name('shoryuken.yml')
      expect(described_class.sqs.config.endpoint.to_s).to eql(sqs_endpoint)
      expect(described_class.sns.config.endpoint.to_s).to eq(sns_endpoint)
    end

    it 'will fallback to default settings if no config file settings or environment variables found' do
      ENV['AWS_SQS_ENDPOINT'] = nil
      ENV['AWS_SNS_ENDPOINT'] = nil
      load_config_file_by_file_name('shoryuken.yml')
      expect(described_class.sqs.config.endpoint.to_s).to eql('https://sqs.us-east-1.amazonaws.com')
      expect(described_class.sns.config.endpoint.to_s).to eq('https://sns.us-east-1.amazonaws.com')
    end
  end

  def load_config_file_by_file_name(file_name)
    path_name = file_name ? File.join(File.expand_path('../../..', __FILE__), 'spec', file_name) : nil
    Shoryuken::EnvironmentLoader.load(config_file: path_name)
  end
end
