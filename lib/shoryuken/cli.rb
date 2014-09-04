$stdout.sync = true

require 'singleton'

module Shoryuken
  class CLI
    include Util
    include Singleton

    def run(options)
      setup_options(options)

      AWS.config options['aws']
      @launcher = Shoryuken::Launcher.new(options).run

      %w[INT QUIT HUP TERM].each do |signal|
        # trap(signal) { @launcher.stop }
      end
    end

    private

    def setup_options(options)
      Shoryuken.options.merge!(options).deep_symbolize_keys
    end
  end
end
