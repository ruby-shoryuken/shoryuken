require 'bundler/gem_tasks'

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

task :push_test, :size do |t, args|
  require 'yaml'
  require 'shoryuken'

  config = YAML.load File.read(File.join(File.expand_path('..', __FILE__), 'shoryuken.yml'))

  AWS.config(config['aws'])

  (args[:size] || 1).to_i.times do |i|
    Shoryuken::Client.queues('shoryuken').send_message("shoryuken #{i}")
    Shoryuken::Client.queues('uppercut').send_message("uppercut #{i}")
    Shoryuken::Client.queues('sidekiq').send_message("sidekiq #{i}")
  end
end
