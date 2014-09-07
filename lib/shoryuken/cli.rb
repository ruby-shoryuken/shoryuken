$stdout.sync = true

require 'singleton'

module Shoryuken
  class CLI
    include Util
    include Singleton

    def run(options)
      self_read, self_write = IO.pipe

      %w(INT TERM USR1 USR2 TTIN).each do |sig|
        trap sig do
          self_write.puts(sig)
        end
      end

      setup_options(options)

      AWS.config options['aws']

      launcher = Shoryuken::Launcher.new(options)

      begin
        launcher.run

        while readable_io = IO.select([self_read])
          signal = readable_io.first[0].gets.strip
          handle_signal(signal)
        end
      rescue Interrupt
        logger.info 'Shutting down'
        launcher.stop
        exit(0)
      end
    end

    private

    def handle_signal(sig)
      Shoryuken.logger.debug "Got #{sig} signal"

      raise Interrupt
    end

    def setup_options(options)
      Shoryuken.options.merge!(options).deep_symbolize_keys
    end
  end
end
