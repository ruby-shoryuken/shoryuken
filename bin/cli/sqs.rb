require 'date'

# rubocop:disable Metrics/AbcSize, Metrics/BlockLength
module Shoryuken
  module CLI
    class SQS < Base
      namespace :sqs

      no_commands do
        def normalize_dump_message(message)
          message[:id] = message.delete(:message_id)
          message[:message_body] = message.delete(:body)
          message.delete(:receipt_handle)
          message.delete(:md5_of_body)
          message.delete(:md5_of_message_attributes)
          message
        end

        def sqs
          @_sqs ||= Aws::SQS::Client.new
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
              say "Could not delete #{failure.id}, code: #{failure.code}", :yellow
            end
          end
        end

        def batch_send(url, messages)
          messages.to_a.flatten.map(&method(:normalize_dump_message)).each_slice(10) do |batch|
            sqs.send_message_batch(queue_url: url, entries: batch).failed.any? do |failure|
              say "Could not requeue #{failure.id}, code: #{failure.code}", :yellow
            end
          end
        end

        def find_all(url, limit, &block)
          count = 0
          batch_size = limit > 10 ? 10 : limit

          loop do
            n = limit - count
            batch_size = n if n < batch_size

            messages = sqs.receive_message(
              queue_url: url,
              max_number_of_messages: batch_size,
              message_attribute_names: ['All']
            ).messages

            messages.each { |m| yield m }

            count += messages.size

            break if count >= limit
            break if messages.empty?
          end

          count
        end

        def list_and_print_queues(urls)
          attrs = %w(QueueArn ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible LastModifiedTimestamp)

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
      method_option :watch,          aliases: '-w',  type: :boolean,              desc: 'watch queues'
      method_option :watch_interval,                 type: :numeric, default: 10, desc: 'watch interval'
      def ls(queue_name_prefix = '')
        trap('SIGINT', 'EXIT') # expect ctrl-c from loop

        urls = sqs.list_queues(queue_name_prefix: queue_name_prefix).queue_urls

        loop do
          list_and_print_queues(urls)

          break unless options[:watch]

          sleep options[:watch_interval]
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
      def requeue(queue_name, path)
        fail_task "Path #{path} not found" unless File.exist?(path)

        messages = File.readlines(path).map { |line| JSON.parse(line, symbolize_names: true) }

        batch_send(find_queue_url(queue_name), messages)

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
    end
  end
end
