# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'shoryuken/version'

Gem::Specification.new do |spec|
  spec.name          = 'shoryuken'
  spec.version       = Shoryuken::VERSION
  spec.authors       = ['Pablo Cantero']
  spec.email         = ['pablo@pablocantero.com']
  spec.description = spec.summary = 'Shoryuken is a super efficient AWS SQS thread based message processor'
  spec.homepage      = 'https://github.com/phstc/shoryuken'
  spec.license       = 'LGPL-3.0'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = %w(shoryuken)
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.6'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'pry-byebug'
  spec.add_development_dependency 'dotenv'

  spec.add_dependency 'aws-sdk-core', '~> 2'
  spec.add_dependency 'concurrent-ruby'
  spec.add_dependency 'thor'
end
