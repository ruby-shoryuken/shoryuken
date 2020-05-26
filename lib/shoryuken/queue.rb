module Shoryuken
  class Queue
    include Util

    FIFO_ATTR               = 'FifoQueue'.freeze
    MESSAGE_GROUP_ID        = 'ShoryukenMessage'.freeze
    VISIBILITY_TIMEOUT_ATTR = 'VisibilityTimeout'.freeze

    attr_accessor :name, :client, :url

    def initialize(client, name_or_url_or_arn)
      self.client = client
      set_name_and_url(name_or_url_or_arn)
    end

    def visibility_timeout
      # Always lookup for the latest visibility when cache is disabled
      # setting it to nil, forces re-lookup
      @_visibility_timeout = nil unless Shoryuken.cache_visibility_timeout?
      @_visibility_timeout ||= queue_attributes.attributes[VISIBILITY_TIMEOUT_ATTR].to_i
    end

    def delete_messages(options)
      client.delete_message_batch(
        options.merge(queue_url: url)
      ).failed.any? do |failure|
        logger.error do
          "Could not delete #{failure.id}, code: '#{failure.code}', message: '#{failure.message}', sender_fault: #{failure.sender_fault}"
        end
      end
    end

    def send_message(options)
      options = sanitize_message!(options).merge(queue_url: url)

      Shoryuken.client_middleware.invoke(options) do
        client.send_message(options)
      end
    end

    def send_messages(options)
      client.send_message_batch(sanitize_messages!(options).merge(queue_url: url))
    end

    def receive_messages(options)
      client.receive_message(options.merge(queue_url: url)).messages.map { |m| Message.new(client, self, m) }
    end

    def fifo?
      # Make sure the memoization work with boolean to avoid multiple calls to SQS
      # see https://github.com/phstc/shoryuken/pull/529
      return @_fifo if defined?(@_fifo)
      @_fifo = queue_attributes.attributes[FIFO_ATTR] == 'true'
    end

    private

    def set_by_name(name)
      self.name = name
      self.url  = client.get_queue_url(queue_name: name).queue_url
    end

    def set_by_url(url)
      self.name = url.split('/').last
      self.url  = url
    end

    def arn_to_url(arn_str)
      _,_,_,region,account_id,resource = arn_str.split(":")

      required = [region, account_id, resource]

      raise "please pass a shoryuken queue ARN containing, account_id, and resource values (#{arn_str})" if required.any?(&:empty?)

      result = "https://sqs.#{region}.amazonaws.com/#{account_id}/#{resource}"
    end

    def set_name_and_url(name_or_url_or_arn)
      if name_or_url_or_arn.include?('://')
        set_by_url(name_or_url_or_arn)

        # anticipate the fifo? checker for validating the queue URL
        return fifo?
      end

      if name_or_url_or_arn.include?('arn:')
        url = arn_to_url(name_or_url_or_arn)
        set_by_url(url)
        return
      end

      set_by_name(name_or_url_or_arn)
    rescue Aws::Errors::NoSuchEndpointError, Aws::SQS::Errors::NonExistentQueue => ex
      raise ex, "The specified queue #{name_or_url_or_arn} does not exist."
    end

    def queue_attributes
      # Note: Retrieving all queue attributes as requesting `FifoQueue` on non-FIFO queue raises error.
      # See issue: https://github.com/aws/aws-sdk-ruby/issues/1350
      client.get_queue_attributes(queue_url: url, attribute_names: ['All'])
    end

    def sanitize_messages!(options)
      if options.is_a?(Array)
        entries = options.map.with_index do |m, index|
          { id: index.to_s }.merge(m.is_a?(Hash) ? m : { message_body: m })
        end

        options = { entries: entries }
      end

      options[:entries].each(&method(:sanitize_message!))

      options
    end

    def add_fifo_attributes!(options)
      return unless fifo?

      options[:message_group_id]         ||= MESSAGE_GROUP_ID
      options[:message_deduplication_id] ||= Digest::SHA256.hexdigest(options[:message_body].to_s)

      options
    end

    def sanitize_message!(options)
      options = { message_body: options } if options.is_a?(String)

      if (body = options[:message_body]).is_a?(Hash)
        options[:message_body] = JSON.dump(body)
      end

      add_fifo_attributes!(options)

      options
    end
  end
end
