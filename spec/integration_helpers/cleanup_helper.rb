# frozen_string_literal: true

# Resources a single spec creates and cleans up afterwards
module CleanupHelper
  # Yields a new queue (with fifo: a FIFO queue with content-based deduplication) and a temporary directory, and
  # deletes both afterwards
  def with_queue_and_dir(attributes: {}, fifo: false)
    dir = Dir.mktmpdir
    queue = fifo ? "#{DT.uuid}.fifo" : DT.uuid
    fifo ? create_fifo_queue(queue) : create_test_queue(queue, attributes: attributes)

    yield queue, dir
  ensure
    delete_test_queue(queue) if queue
    FileUtils.remove_entry(dir) if dir
  end
end
