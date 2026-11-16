# frozen_string_literal: true

require 'optparse'

module Shoryuken
  module CLI
    # Invalid command line input: its message is printed without a backtrace and the process exits with status 1
    class Error < StandardError; end

    # Base class for CLI commands: a small command dispatcher on top of the stdlib OptionParser
    class Base
      # Switches that print help in place of running a command
      HELP_SWITCHES = %w[-h --help].freeze

      # Values accepted by numeric options
      NUMERIC = /\A[-+]?(\d*\.\d+|\d+)\z/

      # Inline values Thor took for a boolean switch (`--verbose=false`)
      TRUE_VALUES = %w[true TRUE t T].freeze
      FALSE_VALUES = %w[false FALSE f F].freeze

      # ANSI color codes used by {#say}
      COLORS = { red: 31, green: 32, yellow: 33 }.freeze

      # An option of a command
      Option = Struct.new(:name, :aliases, :type, :default, :desc, keyword_init: true)

      # A command with its usage line, description and options
      Command = Struct.new(:name, :usage, :desc, :options, keyword_init: true)

      # A nested command set, such as `shoryuken sqs`
      Subcommand = Struct.new(:name, :klass, :usage, :desc, keyword_init: true)

      private_constant :NUMERIC, :TRUE_VALUES, :FALSE_VALUES, :COLORS, :Option, :Command, :Subcommand

      class << self
        # Sets or returns the command set name shown after `shoryuken` in usage lines
        #
        # @param name [Symbol, nil] the name to set
        # @return [Symbol, nil] the name
        def namespace(name = nil)
          @namespace = name if name
          @namespace
        end

        # @return [Hash{String => Command}] the commands by name
        def commands
          @commands ||= {}
        end

        # @return [Hash{String => Subcommand}] the nested command sets by name
        def subcommands
          @subcommands ||= {}
        end

        # @return [Array<Option>] the options every command of this class accepts
        def class_options
          @class_options ||= []
        end

        # Adds an option every command of this class accepts
        #
        # @param name [Symbol] the option name
        # @param options [Hash] :aliases, :type, :default and :desc
        # @return [void]
        def class_option(name, **options)
          class_options << Option.new(name: name, **options)
        end

        # Describes the command defined next
        #
        # @param usage [String] the usage line, command name first
        # @param description [String] the description
        # @return [void]
        def desc(usage, description)
          @usage = usage
          @desc = description
        end

        # Adds an option to the command defined next
        #
        # @param name [Symbol] the option name
        # @param options [Hash] :aliases, :type, :default and :desc
        # @return [void]
        def method_option(name, **options)
          (@method_options ||= []) << Option.new(name: name, **options)
        end

        # Registers the method as a command when {.desc} described it
        #
        # @param name [Symbol] the method name
        # @return [void]
        def method_added(name)
          super
          return unless @usage

          commands[name.to_s] = Command.new(name: name.to_s, usage: @usage, desc: @desc, options: @method_options || [])
          @usage = @desc = @method_options = nil
        end

        # Registers a nested command set
        #
        # @param name [String] the command name
        # @param klass [Class] the {Base} subclass that holds the commands
        # @param usage [String] the usage line
        # @param description [String] the description
        # @return [void]
        def subcommand(name, klass, usage, description)
          subcommands[name] = Subcommand.new(name: name, klass: klass, usage: usage, desc: description)
        end

        # Runs the command the arguments name; invalid input prints its error and exits with status 1
        #
        # @param argv [Array<String>] the command line arguments
        # @return [void]
        def start(argv = ARGV)
          dispatch(argv.dup)
        rescue Error => e
          $stderr.puts(e.message)
          exit(1)
        rescue Errno::EPIPE
          nil
        end

        protected

        # @param arg [String, nil] an argument
        # @return [Boolean] whether the argument asks for help
        def help_switch?(arg)
          HELP_SWITCHES.include?(arg)
        end

        # Runs the command named by the first argument, or prints the command list
        #
        # @param argv [Array<String>] the command line arguments
        # @return [void]
        def dispatch(argv)
          return print_commands if argv.empty? || help_switch?(argv.first)

          name = find_command(argv.shift)

          if name == 'help'
            help(argv)
          elsif subcommands.key?(name)
            subcommands[name].klass.start(argv)
          else
            run_command(commands[name], argv)
          end
        end

        # Finds a command by its name or a prefix of it
        #
        # @param name [String] the name given on the command line
        # @return [String] the command name
        # @raise [Error] when no command or more than one matches
        def find_command(name)
          names = commands.keys + subcommands.keys + ['help']
          return name if names.include?(name)

          matches = names.select { |command| command.start_with?(name) }
          return matches.first if matches.one?
          raise Error, "Could not find command #{name.inspect}." if matches.empty?

          raise Error, "Ambiguous command #{name} matches [#{matches.sort.join(', ')}]"
        end

        # Parses the options and arguments of a command and runs it
        #
        # @param command [Command] the command
        # @param argv [Array<String>] the arguments after the command name
        # @return [void]
        # @raise [Error] on an unknown option, a bad value or a wrong number of arguments
        def run_command(command, argv)
          return print_command(command) if argv.take_while { |arg| arg != '--' }.intersect?(HELP_SWITCHES)

          options, args = parse(command.options + class_options, argv)
          check_arity(command, args)

          new(options).public_send(command.name, *args)
        end

        private

        # @return [String] the program name and namespace that start every usage line
        def banner
          ['shoryuken', namespace].compact.join(' ')
        end

        # Prints the help of a command, or the command list when no command is given
        #
        # @param argv [Array<String>] the arguments after `help`
        # @return [void]
        def help(argv)
          return print_commands if argv.empty?

          name = find_command(argv.first)

          if name == 'help'
            puts "Usage:\n  #{banner} help [COMMAND]\n\n#{help_description}"
          elsif subcommands.key?(name)
            subcommands[name].klass.start(['help', *argv.drop(1)])
          else
            print_command(commands[name])
          end
        end

        # @return [String] the description of the help command
        def help_description
          return 'Describe subcommands or one specific subcommand' if namespace

          'Describe available commands or one specific command'
        end

        # Prints the command list and the options every command accepts
        #
        # @return [void]
        def print_commands
          rows = commands.values.map { |command| [command.usage, command.desc] }
          rows += subcommands.values.map { |subcommand| [subcommand.usage, subcommand.desc] }
          rows << ['help [COMMAND]', help_description]

          puts 'Commands:'
          print_rows(rows.sort.map { |usage, desc| ["#{banner} #{usage}", desc] })
          print_options(class_options)
        end

        # Prints the usage, options and description of a command
        #
        # @param command [Command] the command
        # @return [void]
        def print_command(command)
          puts "Usage:\n  #{banner} #{command.usage}"
          print_options(command.options + class_options)
          puts "\n#{command.desc}"
        end

        # Prints an options table, with defaults
        #
        # @param options [Array<Option>] the options
        # @return [void]
        def print_options(options)
          return if options.empty?

          rows = options.flat_map do |option|
            switches = [*option.aliases, switch_usage(option)].join(', ')
            switches = "    #{switches}" unless option.aliases
            row = [[switches, option.desc]]
            row << ['', "Default: #{option.default}"] unless option.default.nil? || option.default == {}
            row
          end

          puts "\nOptions:"
          print_rows(rows)
        end

        # @param option [Option] the option
        # @return [String] the long switch with its value placeholder
        def switch_usage(option)
          case option.type
          when :boolean then "--[no-]#{dashed(option)}"
          when :numeric then "--#{dashed(option)}=N"
          when :array then "--#{dashed(option)}=one two three"
          when :hash then "--#{dashed(option)}=key:value"
          else "--#{dashed(option)}=#{option.name.upcase}"
          end
        end

        # Prints two columns, the second one as a comment
        #
        # @param rows [Array<Array(String, String)>] the rows
        # @return [void]
        def print_rows(rows)
          width = rows.map { |left, _| left.size }.max

          rows.each { |left, right| puts "  #{left.ljust(width)}  # #{right}" }
        end

        # @param option [Option] the option
        # @return [String] the option name as used in its long switch
        def dashed(option)
          option.name.to_s.tr('_', '-')
        end

        # Parses the options of a command
        #
        # @param definitions [Array<Option>] the options the command accepts
        # @param argv [Array<String>] the arguments after the command name
        # @return [Array(Hash{Symbol => Object}, Array<String>)] the options and the remaining arguments
        # @raise [Error] on an unknown option or a bad value
        def parse(definitions, argv)
          options = definitions.each_with_object({}) do |option, result|
            result[option.name] = option.default.dup unless option.default.nil?
          end

          argv = extract_lists(definitions, argv, options)

          parser = OptionParser.new
          # Drops OptionParser's own --help, --version and completion switches
          parser.base.long.clear
          parser.require_exact = true
          definitions.each { |option| define(parser, option, options) }

          [options, parse_arguments(parser, argv)]
        rescue OptionParser::NeedlessArgument => e
          raise Error, "Unknown switches #{e.args.first.split('=').first.inspect}"
        rescue OptionParser::MissingArgument => e
          raise Error, "No value provided for option '#{long_switch(definitions, e.args.first)}'"
        end

        # Runs the parser over every argument, collecting the unknown switches
        #
        # @param parser [OptionParser] the parser
        # @param argv [Array<String>] the arguments
        # @return [Array<String>] the arguments that are not options
        # @raise [Error] when there are unknown switches
        def parse_arguments(parser, argv)
          args = []
          unknown = []

          begin
            parser.order!(argv) { |arg| args << arg }
          rescue OptionParser::InvalidOption => e
            unknown << e.args.first.split('=').first
            retry
          end

          raise Error, "Unknown switches #{unknown.map(&:inspect).join(', ')}" if unknown.any?

          args + argv
        end

        # Adds an option to the parser
        #
        # @param parser [OptionParser] the parser
        # @param option [Option] the option
        # @param options [Hash{Symbol => Object}] the parsed options to fill
        # @return [void]
        def define(parser, option, options)
          switches = [*option.aliases]
          long = "--#{dashed(option)}"

          case option.type
          when :boolean
            parser.on(*switches, "--[no-]#{dashed(option)}") { |value| options[option.name] = value }
            parser.on("--skip-#{dashed(option)}") { options[option.name] = false }
          when :numeric
            parser.on(*switches, "#{long} VALUE") { |value| options[option.name] = numeric(long, value) }
          else
            parser.on(*switches, "#{long} VALUE") { |value| options[option.name] = value }
          end
        end

        # Takes the array and hash options with their values out of the arguments (each takes the values that follow
        # it up to the next switch) and normalizes the other switches
        #
        # @param definitions [Array<Option>] the options the command accepts
        # @param argv [Array<String>] the arguments after the command name
        # @param options [Hash{Symbol => Object}] the parsed options to fill
        # @return [Array<String>] the remaining arguments
        # @raise [Error] when an array or hash option has no value
        def extract_lists(definitions, argv, options)
          lists = definitions.select { |option| %i[array hash].include?(option.type) }
          argv = argv.dup
          rest = []

          until argv.empty?
            arg = argv.shift
            break rest.push(arg, *argv) if arg == '--'

            switch, inline = arg.split('=', 2)
            # Thor took `--config_file` as `--config-file`
            switch = switch.tr('_', '-') if switch.start_with?('--')
            option = lists.find { |list| [*list.aliases, "--#{dashed(list)}"].include?(switch) }

            unless option
              # Thor took `--verbose false` as `--verbose=false`
              if inline.nil? && boolean_option(definitions, switch) && (TRUE_VALUES + FALSE_VALUES).include?(argv.first)
                inline = argv.shift
              end

              rest.concat(split_switch(definitions, switch, inline, arg))
              next
            end

            values = inline ? [inline] : []
            values << argv.shift while list_value?(option, argv.first)
            raise Error, "No value provided for option '--#{dashed(option)}'" if values.empty? && option.type == :array

            options[option.name] = option.type == :array ? values : values.to_h { |value| value.split(':', 2) }
          end

          rest
        end

        # @param definitions [Array<Option>] the options the command accepts
        # @param switch [String] the argument up to its first `=`, a long switch with dashes
        # @param inline [String, nil] the argument after its first `=`
        # @param arg [String] the argument as given
        # @return [Array<String>] the argument for OptionParser
        def split_switch(definitions, switch, inline, arg)
          boolean = boolean_option(definitions, switch)
          return ["--no-#{dashed(boolean)}"] if boolean && FALSE_VALUES.include?(inline)
          return [switch] if boolean && TRUE_VALUES.include?(inline)
          # Thor took `-c=3` as `-c 3`
          return [switch, inline] if inline && switch.match?(/\A-[a-zA-Z]\z/)
          return [arg] unless switch.start_with?('--')

          [[switch, inline].compact.join('=')]
        end

        # @param definitions [Array<Option>] the options the command accepts
        # @param switch [String] a switch, a long one with dashes
        # @return [Option, nil] the boolean option of the switch
        def boolean_option(definitions, switch)
          definitions.find do |option|
            option.type == :boolean && [*option.aliases, "--#{dashed(option)}"].include?(switch)
          end
        end

        # @param option [Option] the array or hash option
        # @param arg [String, nil] the next argument
        # @return [Boolean] whether the argument is a value of the option
        def list_value?(option, arg)
          return false if arg.nil? || arg.match?(/\A-{1,2}\S/)

          option.type == :array || arg.include?(':')
        end

        # @param long [String] the long switch
        # @param value [String] the value given
        # @return [Integer, Float] the value as a number
        # @raise [Error] when the value is not a number
        def numeric(long, value)
          raise Error, "Expected numeric value for '#{long}'; got #{value.inspect}" unless value.match?(NUMERIC)

          value.include?('.') ? value.to_f : value.to_i
        end

        # @param definitions [Array<Option>] the options the command accepts
        # @param switch [String] a switch as given on the command line
        # @return [String] the long switch of the option
        def long_switch(definitions, switch)
          option = definitions.find { |definition| [*definition.aliases].include?(switch) }
          option ? "--#{dashed(option)}" : switch
        end

        # @param command [Command] the command
        # @param args [Array<String>] the arguments left after the options
        # @return [void]
        # @raise [Error] when the command does not take that many arguments
        def check_arity(command, args)
          parameters = instance_method(command.name).parameters
          required = parameters.count { |type, _| type == :req }
          optional = parameters.count { |type, _| type == :opt }
          return if args.size.between?(required, required + optional)

          called = args.empty? ? 'no arguments' : "arguments #{args.inspect}"
          raise(
            Error,
            "ERROR: \"#{banner} #{command.name}\" was called with #{called}\nUsage: \"#{banner} #{command.usage}\""
          )
        end
      end

      attr_reader :options

      # @param options [Hash{Symbol => Object}] the parsed options
      def initialize(options = {})
        @options = options
      end

      # Prints a message, in color when the output is a terminal
      #
      # @param message [String] the message
      # @param color [Symbol, nil] :red, :green or :yellow
      # @return [void]
      def say(message, color = nil)
        message = "\e[#{COLORS.fetch(color)}m#{message}\e[0m" if color && colors?
        puts message
      end

      # @return [Boolean] whether {#say} prints in color
      def colors?
        $stdout.tty? && ENV['TERM'] != 'dumb' && ENV['NO_COLOR'].to_s.empty?
      end

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
      def fail_task(msg, quit: true)
        say "[FAIL] #{msg}", :red
        exit(1) if quit
      end
    end
  end
end
