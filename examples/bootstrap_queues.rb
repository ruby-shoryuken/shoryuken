require 'yaml'
require 'shoryuken'

# load SQS credentials
config = YAML.load File.read(File.join(File.expand_path('..', __FILE__), 'shoryuken.yml'))

AWS.config(config['aws'])

sqs = AWS::SQS.new

# create a queue and a respective dead letter queue
# after 7 attempts SQS will move the message to the dead letter queue

dl_name = 'default_failures'
dl = sqs.queues.create(dl_name)

options = {}
options[:redrive_policy] = %Q{{"maxReceiveCount":"7", "deadLetterTargetArn":"#{dl.arn}"}"}

sqs.queues.create('default', options)
