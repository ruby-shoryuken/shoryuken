# frozen_string_literal: true

# Captures errors raised by a block
module ErrorHelper
  # The error_class error the block raises, or nil when it raises none
  def raised_error(error_class)
    yield
    nil
  rescue error_class => e
    e
  end
end
