require 'date'

# rubocop:disable Metrics/BlockLength
module Shoryuken
  module CLI
    class SQS < Base
      # See https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/quotas-messages.html
      MAX_BATCH_SIZE = 256 * 1024

      namespace :sqs
      class_option :endpoint, aliases: '-e', type: :string, default: ENV['SHORYUKEN_SQS_ENDPOINT'], desc: 'Endpoint URL'

      no_commands do
        def normalize_dump_message(message)
          # symbolize_keys is needed for keeping it compatible with `requeue`
          attributes = message[:attributes].symbolize_keys
          {
            id: message[:message_id],
            message_body: message[:body],
            message_attributes: message[:message_attributes],
            message_deduplication_id: attributes[:MessageDeduplicationId],
            message_group_id: attributes[:MessageGroupId]
          }
        end

        def client_options
          endpoint = options[:endpoint]
          {}.tap do |hash|
            hash[:endpoint] = endpoint unless endpoint.to_s.empty?
          end
        end

        def sqs
          @_sqs ||= Aws::SQS::Client.new(client_options)
        end

        def find_queue_url(queue_name)
          sqs.get_queue_url(queue_name: queue_name).queue_url
        rescue Aws::SQS::Errors::NonExistentQueue
          fail_task "The specified queue #{queue_name} does not exist"
        end

        def batch_delete(url, messages)
          messages.to_a.flatten.each_slice(10) do |batch|
            sqs.delete_message_batch(
              queue_url: url,
              entries: batch.map { |message| { id: message.message_id, receipt_handle: message.receipt_handle } }
            ).failed.any? do |failure|
              say(
                "Could not delete #{failure.id}, code: #{failure.code}, message: #{failure.message}, sender_fault: #{failure.sender_fault}",
                :yellow
              )
            end
          end
        end

        def batch_send(url, messages, max_batch_size = 10)
          messages = messages.to_a.flatten.map(&method(:normalize_dump_message))
          batch_send_normalized_messages url, messages, max_batch_size
        end

        def batch_send_normalized_messages(url, messages, max_batch_size)
          # Repeatedly take the longest prefix of messages such that
          # 1. The number of messages is less than or equal to max_batch_size
          # 2. The total message payload size is less than or equal to the
          #    batch payload limit
          while messages.size.positive?
            batch_size = max_batch_size
            loop do
              batch = messages.take batch_size

              unless batch.size == 1 || batch_payload_size(batch) <= MAX_BATCH_SIZE
                batch_size = batch.size - 1
                next
              end

              sqs.send_message_batch(queue_url: url, entries: batch).failed.any? do |failure|
                say "Could not requeue #{failure.id}, code: #{failure.code}", :yellow
              end
              messages = messages.drop batch.size
              break
            end
          end
        end

        def batch_payload_size(messages)
          messages.sum(&method(:message_size))
        end

        def message_size(message)
          attribute_size = (message[:message_attributes] || []).sum do |name, value|
            name_size = name.to_s.bytesize
            data_type_size = value[:data_type].bytesize
            value_size = if value[:string_value]
                           value[:string_value].bytesize
                         elsif value[:binary_value]
                           value[:binary_value].bytesize
                         end
            name_size + data_type_size + value_size
          end

          body_size = message[:message_body].bytesize

          attribute_size + body_size
        end

        def find_all(url, limit)
          count = 0
          batch_size = limit > 10 ? 10 : limit

          loop do
            n = limit - count
            batch_size = n if n < batch_size

            messages = sqs.receive_message(
              queue_url: url,
              max_number_of_messages: batch_size,
              attribute_names: ['All'],
              message_attribute_names: ['All']
            ).messages || []

            messages.each { |m| yield m }

            count += messages.size

            break if count >= limit
            break if messages.empty?
          end

          count
        end

        def list_and_print_queues(urls)
          attrs = %w[QueueArn ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible LastModifiedTimestamp]

          entries = urls.map { |u| sqs.get_queue_attributes(queue_url: u, attribute_names: attrs).attributes }.map do |q|
            [
              q['QueueArn'].split(':').last,
              q['ApproximateNumberOfMessages'],
              q['ApproximateNumberOfMessagesNotVisible'],
              Time.at(q['LastModifiedTimestamp'].to_i)
            ]
          end

          entries.unshift(['Queue', 'Messages Available', 'Messages Inflight', 'Last Modified'])

          print_table(entries)
        end

        def dump_file(path, queue_name)
          File.join(path, "#{queue_name}-#{Date.today}.jsonl")
        end
      end

      desc 'ls [QUEUE-NAME-PREFIX]', 'Lists queues'
      method_option :watch,    aliases: '-w', type: :boolean, desc: 'watch queues'
      method_option :interval, aliases: '-n', type: :numeric, default: 2, desc: 'watch interval in seconds'
      def ls(queue_name_prefix = '')
        trap('SIGINT', 'EXIT') # expect ctrl-c from loop

        urls = sqs.list_queues(queue_name_prefix: queue_name_prefix).queue_urls

        loop do
          list_and_print_queues(urls)

          break unless options[:watch]

          sleep options[:interval]
          puts
        end
      end

      desc 'dump QUEUE-NAME', 'Dumps messages from a queue into a JSON lines file'
      method_option :number, aliases: '-n', type: :numeric, default: Float::INFINITY, desc: 'number of messages to dump'
      method_option :path,   aliases: '-p', type: :string,  default: './',            desc: 'path to save the dump file'
      method_option :delete, aliases: '-d', type: :boolean, default: true,            desc: 'delete from the queue'
      def dump(queue_name)
        path = dump_file(options[:path], queue_name)

        fail_task "File #{path} already exists" if File.exist?(path)

        url = find_queue_url(queue_name)

        messages = []

        file = nil

        count = find_all(url, options[:number]) do |m|
          file ||= File.open(path, 'w')

          file.puts(JSON.dump(m.to_h))

          messages << m if options[:delete]
        end

        batch_delete(url, messages) if options[:delete]

        if count.zero?
          say "Queue #{queue_name} is empty", :yellow
        else
          say "Dump saved in #{path} with #{count} messages", :green
        end
      ensure
        file.close if file
      end

      desc 'requeue QUEUE-NAME PATH', 'Requeues messages from a dump file'
      method_option :batch_size, aliases: '-n', type: :numeric, default: 10, desc: 'maximum number of messages per batch to send'
      def requeue(queue_name, path)
        fail_task "Path #{path} not found" unless File.exist?(path)

        messages = File.readlines(path).map { |line| JSON.parse(line, symbolize_names: true) }

        batch_send(find_queue_url(queue_name), messages, options[:batch_size])

        say "Requeued #{messages.size} messages from #{path} to #{queue_name}", :green
      end

      desc 'mv QUEUE-NAME-SOURCE QUEUE-NAME-TARGET', 'Moves messages from one queue (source) to another (target)'
      method_option :number, aliases: '-n', type: :numeric, default: Float::INFINITY, desc: 'number of messages to move'
      method_option :delete, aliases: '-d', type: :boolean, default: true,            desc: 'delete from the queue'
      def mv(queue_name_source, queue_name_target)
        url_source = find_queue_url(queue_name_source)
        messages = []

        count = find_all(url_source, options[:number]) do |m|
          messages << m
        end

        batch_send(find_queue_url(queue_name_target), messages.map(&:to_h))
        batch_delete(url_source, messages) if options[:delete]

        if count.zero?
          say "Queue #{queue_name_source} is empty", :yellow
        else
          say "Moved #{count} messages from #{queue_name_source} to #{queue_name_target}", :green
        end
      end

      desc 'purge QUEUE-NAME', 'Deletes the messages in a queue'
      def purge(queue_name)
        sqs.purge_queue(queue_url: find_queue_url(queue_name))

        say "Purge request sent for #{queue_name}. The message deletion process takes up to 60 seconds", :yellow
      end

      desc 'create QUEUE-NAME', 'Create a queue'
      method_option :attributes, aliases: '-a', type: :hash, default: {}, desc: 'queue attributes'
      def create(queue_name)
        attributes = options[:attributes]
        attributes['FifoQueue'] ||= 'true' if queue_name.end_with?('.fifo')

        queue_url = sqs.create_queue(queue_name: queue_name, attributes: attributes).queue_url

        say "Queue #{queue_name} was successfully created. Queue URL #{queue_url}", :green
      end

      desc 'delete QUEUE-NAME', 'delete a queue'
      def delete(queue_name)
        sqs.delete_queue(queue_url: find_queue_url(queue_name))

        say "Queue #{queue_name} was successfully delete", :green
      end
    end
  end
end
