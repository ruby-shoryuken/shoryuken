class RedrivePolicyRegistry
  def initialize
    @policy_registry = {}
  end

  def fetch(message_queue_name)
    unless @policy_registry[message_queue_name]
      redrive_policy_json = JSON.parse(Shoryuken::Client.queues(message_queue_name).redrive_policy)
      @policy_registry[message_queue_name] = redrive_policy_json['maxReceiveCount']
    end
    @policy_registry[message_queue_name]
  end
end
