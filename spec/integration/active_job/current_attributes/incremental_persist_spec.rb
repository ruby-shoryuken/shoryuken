# frozen_string_literal: true

# CurrentAttributes registered one class per persist call are all preserved.
#
# persist derived each storage key from the per-call index, so calling it once
# per class (as an app might across several initializers) made the third call
# reuse "cattr_0" and silently overwrite the second class - its attributes were
# then never serialized or restored.

setup_sqs
setup_active_job

require 'active_support/current_attributes'
require 'shoryuken/active_job/current_attributes'

queue_name = DT.queue
create_test_queue(queue_name)

class CurrentA < ActiveSupport::CurrentAttributes
  attribute :a_val
end

class CurrentB < ActiveSupport::CurrentAttributes
  attribute :b_val
end

class CurrentC < ActiveSupport::CurrentAttributes
  attribute :c_val
end

# Registered incrementally, one class per call.
Shoryuken::ActiveJob::CurrentAttributes.persist(CurrentA)
Shoryuken::ActiveJob::CurrentAttributes.persist(CurrentB)
Shoryuken::ActiveJob::CurrentAttributes.persist(CurrentC)

# Every class must be registered, each under a distinct storage key.
registered = Shoryuken::ActiveJob::CurrentAttributes.cattrs
assert_equal(
  %w[CurrentA CurrentB CurrentC],
  registered.values.sort,
  'every persisted CurrentAttributes class must be registered (none silently dropped)'
)
assert_equal(3, registered.keys.uniq.size, 'each class must use a distinct storage key')

class IncrementalCurrentJob < ActiveJob::Base
  def perform
    DT[:executions] << {
      a_val: CurrentA.a_val,
      b_val: CurrentB.b_val,
      c_val: CurrentC.c_val
    }
  end
end

IncrementalCurrentJob.queue_as(queue_name)

Shoryuken.add_group('default', 1)
Shoryuken.add_queue(queue_name, 1, 'default')
Shoryuken.register_worker(queue_name, Shoryuken::ActiveJob::JobWrapper)

CurrentA.a_val = 'a-value'
CurrentB.b_val = 'b-value'
CurrentC.c_val = 'c-value'

IncrementalCurrentJob.perform_later

CurrentA.reset
CurrentB.reset
CurrentC.reset

poll_queues_until(timeout: 30) { DT[:executions].size >= 1 }

result = DT[:executions].first
assert_equal('a-value', result[:a_val])
assert_equal('b-value', result[:b_val], 'the second incrementally-persisted class must not be dropped')
assert_equal('c-value', result[:c_val])
