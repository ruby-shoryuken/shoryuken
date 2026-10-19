# frozen_string_literal: true

module Shoryuken
  module Contractable
    # Representation of a single validation rule
    Rule = Struct.new(:path, :type, :validator)
  end
end
