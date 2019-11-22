# ActiveJob docs: http://edgeguides.rubyonrails.org/active_job_basics.html
# Example adapters ref: https://github.com/rails/rails/tree/master/activejob/lib/active_job/queue_adapters
 module ActiveJob
   module QueueAdapters
     # == Shoryuken concurrent adapter for Active Job
     #
     # This adapter sends messages asynchronously (ie non-blocking) and allows
     # the caller to set up handlers for both success and failure
     #
     # To use this adapter, set up as:
     #
     # adapter = ActiveJob::QueueAdapters::ShoryukenConcurrentSendAdapter.new
		 # adapter.success_handler = ->(job, options) { StatsD.increment(job.class.name + "success") }
		 # adapter.error_handler = ->(err, (job, options)) { StatsD.increment(job.class.name + "failure") }
		 #
		 # config.active_job.queue_adapter = adapter
     class ShoryukenConcurrentSendAdapter < ShoryukenAdapter

       attr_accessor :error_handler
       attr_accessor :success_handler

       def initialize
				 self.error_handler = ->(error, job, options) do
					 Shoryuken.logger.warn("Failed to enqueue job: #{job.inspect} due to error: #{error}")
				 end
         self.success_handler = ->(_job, _options) { nil }
       end

       def enqueue(job, options = {})
         send_concurrently(job, options) { |job, options| super(job, options) }
       end

       private

       def send_concurrently(job, options)
         Concurrent::Promises
					 .future(job, options) { |f_job, f_options| yield(f_job, f_options) }
           .then(job, options) { |f_job, f_options| success_handler.call(f_job, f_options) }
           .rescue(job, options) { |err, (f_job, f_options)| error_handler.call(err, f_job, f_options) }
       end
     end
   end
 end
