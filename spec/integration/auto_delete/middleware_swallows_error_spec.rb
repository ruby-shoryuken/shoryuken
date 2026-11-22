# frozen_string_literal: true

# This spec tests how auto_delete treats a worker error that a global server
# middleware rescues.
#
# A middleware added with `chain.add` runs inside AutoDelete. When it rescues
# the worker error and does not raise it again, AutoDelete sees a normal
# return and deletes the message, so it never comes back. When it raises the
# error again, the message stays and comes back after the visibility timeout.
# A middleware added with `chain.prepend` runs outside AutoDelete, so even
# when it swallows the error the message is not deleted.

setup_sqs

Shoryuken.add_group('default', 1)

class ErrorRescuingMiddleware
  def initialize(rescued_queue, reraise)
    @rescued_queue = rescued_queue
    @reraise = reraise
  end

  def call(_worker, queue, _sqs_msg, _body)
    yield
  rescue StandardError => e
    raise unless queue == @rescued_queue

    DT[:rescued] << [queue, e.message]
    raise if @reraise
  end
end

SwallowingMiddleware = Class.new(ErrorRescuingMiddleware)
ReraisingMiddleware = Class.new(ErrorRescuingMiddleware)
PrependedSwallowingMiddleware = Class.new(ErrorRescuingMiddleware)

def create_failing_queue
  queue = DT.uuid
  create_test_queue(queue, attributes: { 'VisibilityTimeout' => '1' })
  Shoryuken.add_queue(queue, 1, 'default')

  Class.new do
    include Shoryuken::Worker

    shoryuken_options queue: queue, auto_delete: true

    define_method(:perform) do |sqs_msg, _body|
      receive_count = sqs_msg.attributes['ApproximateReceiveCount'].to_i
      DT[queue] << receive_count

      raise 'worker failure' if receive_count == 1
    end
  end

  queue
end

def monotonic_now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def rescued_in(queue)
  DT[:rescued].select { |rescued_queue, _| rescued_queue == queue }
end

swallowed_queue = create_failing_queue
reraised_queue = create_failing_queue
prepended_queue = create_failing_queue
queues = [swallowed_queue, reraised_queue, prepended_queue]

Shoryuken.server_middleware do |chain|
  chain.add SwallowingMiddleware, swallowed_queue, false
  chain.add ReraisingMiddleware, reraised_queue, true
  chain.prepend PrependedSwallowingMiddleware, prepended_queue, false
end

queues.each { |queue| Shoryuken::Client.queues(queue).send_message(message_body: queue) }

# Keep polling past the visibility timeout so a swallowed message that was not
# deleted would be received again.
redelivery_deadline = monotonic_now + 5

begin
  poll_queues_until(timeout: 20) do
    DT[swallowed_queue].any? &&
      DT[reraised_queue].size >= 2 &&
      DT[prepended_queue].size >= 2 &&
      queues.all? { |queue| queue_size(queue).zero? } &&
      monotonic_now > redelivery_deadline
  end
ensure
  Shoryuken.server_middleware do |chain|
    [SwallowingMiddleware, ReraisingMiddleware, PrependedSwallowingMiddleware].each { |klass| chain.remove(klass) }
  end
end

# --- chain.add, error swallowed ---
assert_equal([[swallowed_queue, 'worker failure']], rescued_in(swallowed_queue))
assert_equal([1], DT[swallowed_queue], 'auto_delete must delete the message when the middleware swallows the error')

# --- chain.add, error raised again ---
assert_equal([[reraised_queue, 'worker failure']], rescued_in(reraised_queue))
assert_equal([1, 2], DT[reraised_queue], 'the message must come back when the middleware raises the error again')

# --- chain.prepend, error swallowed ---
assert_equal([[prepended_queue, 'worker failure']], rescued_in(prepended_queue))
assert_equal([1, 2], DT[prepended_queue], 'a middleware outside AutoDelete must not make it delete a failed message')

queues.each { |queue| delete_test_queue(queue) }
