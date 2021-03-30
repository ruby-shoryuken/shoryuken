require 'bundler/gem_tasks'
$stdout.sync = true

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.exclude_pattern = 'spec/integration/**/*_spec.rb'
  end

  namespace :spec do
    desc 'Run Rails specs only'
    RSpec::Core::RakeTask.new(:rails) do |t|
      t.pattern = 'spec/shoryuken/{environment_loader_spec,extensions/active_job_*}.rb'
    end

    desc 'Run integration specs only'
    RSpec::Core::RakeTask.new(:integration) do |t|
      t.pattern = 'spec/integration/**/*_spec.rb'
    end
  end
rescue LoadError
end

desc 'Open Shoryuken pry console'
task :console do
  require 'pry'
  require 'shoryuken'

  config_file = File.join File.expand_path(__dir__), 'shoryuken.yml'

  if File.exist? config_file
    config = YAML.load File.read(config_file)

    Aws.config = config['aws']
  end

  def push(queue, message)
    Shoryuken::Client.queues(queue).send_message(message_body: message)
  end

  ARGV.clear
  Pry.start
end
