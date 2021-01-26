source 'https://rubygems.org'

# Specify your gem's dependencies in shoryuken.gemspec
gemspec

group :test do
  gem 'activejob'
  gem 'aws-sdk-core', '~> 3'
  gem 'aws-sdk-sqs'
  gem 'codeclimate-test-reporter', require: nil
  gem 'httparty'
  gem 'multi_xml'
  gem 'simplecov'
end

group :development do
  gem 'appraisal', git: 'https://github.com/thoughtbot/appraisal.git'
  gem 'pry-byebug', '3.9.0'
  gem 'rubocop'
end
