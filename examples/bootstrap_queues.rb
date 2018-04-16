require 'yaml'
require 'shoryuken'

# load SQS credentials
config = YAML.load File.read(File.join(File.expand_path(__dir__), 'shoryuken.yml'))

Aws.config = config['aws']

sqs = Aws::SQS::Client.new

default_queue_url = sqs.create_queue(queue_name: 'default').queue_url

if sqs.config['endpoint'] =~ /amazonaws.com/
  # create a dead letter queue
  # after 7 attempts SQS will move the message to the dead letter queue

  dead_letter_queue_url = sqs.create_queue(queue_name: 'default_failures').queue_url

  dead_letter_queue_arn = sqs.get_queue_attributes(
    queue_url: dead_letter_queue_url,
    attribute_names: %w[QueueArn]
  ).attributes['QueueArn']

  attributes = {}
  attributes['RedrivePolicy'] = %({"maxReceiveCount":"7", "deadLetterTargetArn":"#{dead_letter_queue_arn}"})

  sqs.set_queue_attributes queue_url: default_queue_url, attributes: attributes
end
