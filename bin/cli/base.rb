module Shoryuken
  module CLI
    class Base < Thor
      PRINT_COLUMN_SIZE = 40

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
              column_sizes[i] = e.size if column_sizes[i] < e.size && e.size < PRINT_COLUMN_SIZE
            end
          end

          column_sizes
        end

        def print_format_column(column, size)
          right_padding = 4
          column = column.to_s.ljust(size + right_padding)
          column = "#{column[0...size - 2]}.." if column.size > size + right_padding
          column
        end
      end
    end
  end
end
