# rubocop:disable Metrics/BlockLength
module Shoryuken
  module CLI
    class Base < Thor
      no_commands do
        def print_table(entries)
          column_sizes = print_columns_size(entries)

          entries.map do |entry|
            puts entry.map.with_index { |e, i| print_format_column(e, column_sizes[i]) }.join
          end
        end

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

        def print_format_column(column, size)
          size = 40 if size > 40
          size_with_padding = size + 4
          column = column.to_s.ljust(size_with_padding)
          column = "#{column[0...size - 2]}.." if column.size > size_with_padding
          column
        end

        def fail_task(msg, quit = true)
          say "[FAIL] #{msg}", :red
          exit(1) if quit
        end
      end
    end
  end
end
