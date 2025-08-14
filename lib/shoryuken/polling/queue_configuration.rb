# frozen_string_literal: true

module Shoryuken
  module Polling
    # Configuration object representing a queue and its associated options.
    #
    # This class encapsulates a queue name along with any polling-specific
    # options or metadata. It provides a structured way to pass queue
    # information between polling strategies and the message fetching system.
    #
    # The class extends Struct to provide attribute accessors for name and options
    # while adding custom behavior for equality comparison and string representation.
    #
    # @example Creating a basic queue configuration
    #   config = QueueConfiguration.new('my_queue', {})
    #   config.name     # => 'my_queue'
    #   config.options  # => {}
    #
    # @example Creating a queue configuration with options
    #   config = QueueConfiguration.new('priority_queue', { priority: :high })
    #   config.name     # => 'priority_queue'
    #   config.options  # => { priority: :high }
    #
    # @example Comparing configurations
    #   config1 = QueueConfiguration.new('queue', {})
    #   config2 = QueueConfiguration.new('queue', {})
    #   config1 == config2  # => true
    #   config1 == 'queue'  # => true (when options are empty)
    #
    # @attr_reader [String] name The name of the queue
    # @attr_reader [Hash] options Additional options or metadata for the queue
    QueueConfiguration = Struct.new(:name, :options) do
      # Generates a hash value based on the queue name.
      #
      # This method ensures that QueueConfiguration objects can be used
      # as hash keys and that configurations with the same queue name
      # will have the same hash value regardless of their options.
      #
      # @return [Integer] Hash value based on the queue name
      def hash
        name.hash
      end

      # Compares this configuration with another object for equality.
      #
      # Two QueueConfiguration objects are equal if they have the same name
      # and options. For convenience, a configuration with empty options can
      # also be compared directly with a string queue name.
      #
      # @param other [Object] The object to compare with
      # @return [Boolean] true if the objects are considered equal
      #
      # @example Comparing with another QueueConfiguration
      #   config1 = QueueConfiguration.new('queue', {})
      #   config2 = QueueConfiguration.new('queue', {})
      #   config1 == config2  # => true
      #
      # @example Comparing with a string (only when options are empty)
      #   config = QueueConfiguration.new('queue', {})
      #   config == 'queue'  # => true
      #
      #   config_with_options = QueueConfiguration.new('queue', { weight: 5 })
      #   config_with_options == 'queue'  # => false
      def ==(other)
        case other
        when String
          if options.empty?
            name == other
          else
            false
          end
        else
          super
        end
      end

      alias_method :eql?, :==

      # Returns a string representation of the queue configuration.
      #
      # For configurations with empty options, returns just the queue name.
      # For configurations with options, returns a detailed representation
      # showing both the name and the options hash.
      #
      # @return [String] String representation of the configuration
      #
      # @example Simple queue without options
      #   config = QueueConfiguration.new('simple_queue', {})
      #   config.to_s  # => 'simple_queue'
      #
      # @example Queue with options
      #   config = QueueConfiguration.new('complex_queue', { priority: :high })
      #   config.to_s  # => '#<QueueConfiguration complex_queue options={:priority=>:high}>'
      def to_s
        if options&.empty?
          name
        else
          "#<QueueConfiguration #{name} options=#{options.inspect}>"
        end
      end
    end
  end
end
