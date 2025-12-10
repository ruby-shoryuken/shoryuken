# frozen_string_literal: true

module Shoryuken
  module CLI
    # Base class for CLI commands providing common helper methods.
    class Base < Thor
      no_commands do
        # Prints entries as a formatted table
        #
        # @param entries [Array<Array>] rows to print as a table
        # @return [void]
        def print_table(entries)
          column_sizes = print_columns_size(entries)

          entries.map do |entry|
            puts entry.map.with_index { |e, i| print_format_column(e, column_sizes[i]) }.join
          end
        end

        # Calculates the maximum width for each column
        #
        # @param entries [Array<Array>] the table rows
        # @return [Hash<Integer, Integer>] column index to max width mapping
        def print_columns_size(entries)
          column_sizes = Hash.new(0)

          entries.each do |entry|
            entry.each_with_index do |e, i|
              e = e.to_s
              column_sizes[i] = e.size if column_sizes[i] < e.size
            end
          end

          column_sizes
        end

        # Formats a column value with padding
        #
        # @param column [Object] the column value to format
        # @param size [Integer] the target width
        # @return [String] the formatted column
        def print_format_column(column, size)
          size_with_padding = size + 4
          column.to_s.ljust(size_with_padding)
        end

        # Outputs a failure message and optionally exits
        #
        # @param msg [String] the failure message
        # @param quit [Boolean] whether to exit the program
        # @return [void]
        def fail_task(msg, quit = true)
          say "[FAIL] #{msg}", :red
          exit(1) if quit
        end
      end
    end
  end
end
