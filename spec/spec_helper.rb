require 'bundler/setup'
Bundler.setup

require 'pry-byebug'
require 'celluloid'
require 'shoryuken'
require 'json'
require 'multi_xml'

require 'codeclimate-test-reporter'
CodeClimate::TestReporter.start

config_file = File.join(File.expand_path('../..', __FILE__), 'spec', 'shoryuken.yml')

Shoryuken::EnvironmentLoader.load(config_file: config_file)

Shoryuken.logger.level = Logger::UNKNOWN
Celluloid.logger.level = Logger::UNKNOWN

# I'm not sure whether this is an issue specific to running Shoryuken against github.com/comcast/cmb
# as opposed to AWS itself, but sometimes the receive_messages call returns XML that looks like this:
#
# <ReceiveMessageResponse>\n\t<ReceiveMessageResult>\n\t</ReceiveMessageResult> ... </ReceiveMessageResponse>
#
# The default MultiXML parser is ReXML, which seems to mishandle \n\t chars. Nokogiri seems to be
# the only one that correctly ignore this whitespace.
MultiXml.parser = :nokogiri

class TestWorker
  include Shoryuken::Worker

  shoryuken_options queue: 'default'

  def perform(sqs_msg, body); end
end

RSpec.configure do |config|
  config.filter_run_excluding slow: true unless ENV['SPEC_ALL']

  config.before do
    # remove doubles, preventing:
    # Double "Queue" was originally created in one example but has leaked into another example and can no longer be used.
    # rspec-mocks' doubles are designed to only last for one example, and you need to create a new one in each example you wish to use it for.
    Shoryuken::Client.class_variable_set :@@queues, {}
    Shoryuken::Client.class_variable_set :@@visibility_timeouts, {}

    Shoryuken::Client.sqs = nil
    Shoryuken::Client.sqs_resource = nil
    Shoryuken::Client.sns = nil

    Shoryuken.queues.clear

    Shoryuken.options[:concurrency] = 1
    Shoryuken.options[:delay]       = 1
    Shoryuken.options[:timeout]     = 1
    Shoryuken.options[:aws].delete(:receive_message)

    TestWorker.get_shoryuken_options.clear
    TestWorker.get_shoryuken_options['queue'] = 'default'

    Shoryuken.worker_registry.clear
    Shoryuken.register_worker('default', TestWorker)
  end
end
