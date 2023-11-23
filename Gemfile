source 'https://rubygems.org'

# Specify your gem's dependencies in shoryuken.gemspec
gemspec

group :test do
  gem 'activejob'
  gem 'aws-sdk-core', '~> 3'
  # Pin to 1.65.0 because of below issues:
  # - https://github.com/ruby-shoryuken/shoryuken/pull/753#issuecomment-1822720647
  # - https://github.com/getmoto/moto/issues/7054
  gem 'aws-sdk-sqs', '1.65.0'
  gem 'codeclimate-test-reporter', require: nil
  gem 'httparty'
  gem 'multi_xml'
  gem 'simplecov'
end

group :development do
  gem 'appraisal', git: 'https://github.com/thoughtbot/appraisal.git'
  gem 'pry-byebug'
  gem 'rubocop', '<= 1.12'
end
