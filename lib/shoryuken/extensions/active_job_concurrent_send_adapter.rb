 module ActiveJob
   module QueueAdapters
     class ShoryukenConcurrentSendAdapter < ShoryukenAdapter

       attr_accessor :error_handler
       attr_accessor :success_handler

       def initialize
         @error_handler = ->(error, job, options) { Shoryuken.logger.warn("Failed to enqueue job: #{job.inspect} due to error: #{error}") }
         @success_handler = ->(job, options) { nil }
       end

       def enqueue(job, options = {})
         send_concurrently(job, options) { |job, options| super(job, options) }
       end

       private

       def send_concurrently(job, options)
         Concurrent::Promises.future(job, options) { |job, options| yield(job, options) }
           .then(job, options) { |job, options| success_handler.call(job, options) }
           .rescue(job, options) { |err, (job, options)| error_handler.call(err, job, options) }
       end
     end
   end
 end
