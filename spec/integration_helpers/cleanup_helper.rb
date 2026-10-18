# frozen_string_literal: true

# Resources a single spec creates and cleans up afterwards
module CleanupHelper
  # Yields a new queue and a temporary directory, and deletes both afterwards
  def with_queue_and_dir(attributes: {})
    dir = Dir.mktmpdir
    queue = DT.uuid
    create_test_queue(queue, attributes: attributes)

    yield queue, dir
  ensure
    delete_test_queue(queue) if queue
    FileUtils.remove_entry(dir) if dir
  end
end
