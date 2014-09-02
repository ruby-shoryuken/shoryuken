require 'bundler/setup'
Bundler.setup

require 'shoryuken'

Shoryuken::Util.logger.level = Logger::ERROR

RSpec.configure do |config|
end
