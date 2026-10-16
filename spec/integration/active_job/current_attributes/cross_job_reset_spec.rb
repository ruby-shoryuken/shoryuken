# frozen_string_literal: true

# A message without a CurrentAttributes key must not inherit a previous job's
# context. Every registered class is reset after each job - even keyless ones -
# so values set during one job don't leak into the next on a reused worker
# thread.

setup_sqs
setup_active_job

require 'active_support/current_attributes'
require 'shoryuken/active_job/current_attributes'

queue_name = DT.queue
create_test_queue(queue_name)

class LeakCurrent < ActiveSupport::CurrentAttributes
  attribute :user_id
end

Shoryuken::ActiveJob::CurrentAttributes.persist(LeakCurrent)

class CrossJobResetTestJob < ActiveJob::Base
  def perform
    # Record what the worker thread sees at the start of the job, then dirty
    # Current. Without a reset after a keyless job, the second execution on the
    # same thread would observe 'leaked' instead of nil.
    DT[:observed] << LeakCurrent.user_id
    LeakCurrent.user_id = 'leaked'
  end
end

CrossJobResetTestJob.queue_as(queue_name)

# Concurrency 1 so the two jobs run sequentially on the same worker thread.
Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

# Enqueued with an empty context, so both messages carry no cattr key.
CrossJobResetTestJob.perform_later
CrossJobResetTestJob.perform_later

poll_queues_until(timeout: 30) { DT[:observed].size >= 2 }

assert_equal([nil, nil], DT[:observed].first(2),
             "CurrentAttributes leaked across jobs: #{DT[:observed].inspect}")
