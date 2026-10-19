# frozen_string_literal: true

module RuboCop
  module Cop
    module Shoryuken
      # Requires parentheses around the arguments of a call when they span several lines, so that
      # Layout/FirstMethodArgumentLineBreak and Layout/MultilineMethodCallBraceLayout can then put each
      # of them on a new line and the closing parenthesis on its own line.
      #
      # A single argument that spans lines (e.g. `expect(x).to receive(:y).with(...)`) is allowed.
      #
      # @example
      #   # bad
      #   attr_accessor :foo,
      #     :bar
      #
      #   # good
      #   attr_accessor(
      #     :foo,
      #     :bar
      #   )
      class MultilineCallParentheses < Base
        extend AutoCorrector

        MSG = 'Use parentheses for a call whose arguments span several lines.'

        def on_send(node)
          return if node.parenthesized? || node.operator_method? || node.setter_method?
          return unless node.loc.selector
          return unless several_arguments?(node)
          return if node.first_argument.first_line == last_line(node)

          add_offense(node.loc.selector) do |corrector|
            gap = node.loc.selector.end.join(node.first_argument.source_range.begin)
            corrector.replace(gap, '(')
            corrector.insert_after(node.last_argument.source_range, ')')
          end
        end
        alias on_csend on_send

        private

        def several_arguments?(node)
          return true if node.arguments.size > 1

          argument = node.first_argument
          argument&.hash_type? && !argument.braces? && argument.pairs.size > 1
        end

        def last_line(node)
          node.last_argument.source_range.last_line
        end
      end
    end
  end
end
