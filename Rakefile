require 'bundler/gem_tasks'
$stdout.sync = true

desc 'Open Shoryuken pry console'
task :console do
  require 'pry'
  require 'shoryuken'

  config_file = File.join File.expand_path('..', __FILE__), 'shoryuken.yml'

  if File.exist? config_file
    config = YAML.load File.read(config_file)

    AWS.config(config['aws'])
  end

  def push(queue, message)
    Shoryuken::Client.queues(queue).send_message message
  end

  ARGV.clear
  Pry.start
end

desc 'Push test messages to high_priority, default and low_priority'
task :push_test, :size do |t, args|
  require 'yaml'
  require 'shoryuken'

  config = YAML.load File.read(File.join(File.expand_path('..', __FILE__), 'shoryuken.yml'))

  AWS.config(config['aws'])

  Shoryuken::Client.sqs.queues.create('default')
  Shoryuken::Client.sqs.queues.create('high_priority')
  Shoryuken::Client.sqs.queues.create('low_priority')

  (args[:size] || 1).to_i.times.map do |i|
    Thread.new do
      puts "Pushing test ##{i}"

      Shoryuken::Client.queues('high_priority').send_message("test #{i}")
      Shoryuken::Client.queues('default').send_message("test #{i}")
      Shoryuken::Client.queues('low_priority').send_message("test #{i}")
    end
  end.each &:join
end
