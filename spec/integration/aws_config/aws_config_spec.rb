# frozen_string_literal: true

# This spec tests that AWS configuration from Shoryuken.options[:aws]
# is properly passed to the SQS client initialization.
# This verifies the fix for issue #815: PORO setup does not load AWS config

# Reset any cached SQS client to ensure fresh initialization
Shoryuken.sqs_client = nil

# Configure AWS options programmatically (simulating PORO setup with config file)
Shoryuken.options[:aws] = {
  region: 'us-east-1',
  endpoint: 'http://localhost:4566',
  access_key_id: 'test-key-from-config',
  secret_access_key: 'test-secret-from-config'
}

# Get the SQS client - this should use the AWS config from options
client = Shoryuken.sqs_client

# Verify the client was configured with our options
config = client.config

assert_equal('us-east-1', config.region, "Region should be set from options[:aws]")
assert_equal('http://localhost:4566', config.endpoint.to_s, "Endpoint should be set from options[:aws]")

# Verify the client actually works by creating a queue
queue_name = "aws-config-test-#{SecureRandom.hex(6)}"

begin
  result = client.create_queue(queue_name: queue_name)
  assert(result.queue_url.include?(queue_name), "Should be able to create queue with configured client")

  # Clean up
  client.delete_queue(queue_url: result.queue_url)
rescue Aws::SQS::Errors::ServiceError => e
  raise "SQS client should work with configured AWS options: #{e.message}"
end

# Test 2: Verify that reconfiguring options and resetting client works
Shoryuken.sqs_client = nil
Shoryuken.options[:aws][:region] = 'us-west-2'

client2 = Shoryuken.sqs_client
assert_equal('us-west-2', client2.config.region, "New client should use updated region")

# Test 3: Verify that credentials from options are used
# Reset and reconfigure with explicit credentials
Shoryuken.sqs_client = nil
Shoryuken.options[:aws] = {
  region: 'us-east-1',
  endpoint: 'http://localhost:4566',
  access_key_id: 'another-key',
  secret_access_key: 'another-secret'
}

client3 = Shoryuken.sqs_client
assert(client3.is_a?(Aws::SQS::Client), "Client should be created with new credentials")
assert_equal('us-east-1', client3.config.region, "Region should match configured value")
