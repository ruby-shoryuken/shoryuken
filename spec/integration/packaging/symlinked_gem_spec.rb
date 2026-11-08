# frozen_string_literal: true

# This spec tests the installed gem when each of its files is a symlink to a
# file in another directory, as a Bazel sandbox lays out a gem.
#
# `shoryuken start` from that gem loads lib/shoryuken.rb through its symlink
# and processes a message: with Active Job not loaded, and with Active Job
# loaded before Shoryuken, as a Rails app loads it.
#
# Regression: Zeitwerk managed lib/active_job, because the ignored path was
# the resolved directory, outside the loader root. Loading raised a NameError
# from lib/active_job/extensions.rb without Active Job, and
# Zeitwerk::NameError for ActiveJob::Extensions with it.

setup_sqs
setup_active_job

class SymlinkedGemJob < ActiveJob::Base
  def perform(_marker); end
end

def link_gem_files(gem_dir, target_dir)
  FileUtils.mv(gem_dir, target_dir)

  Dir.glob('**/*', base: target_dir).each do |path|
    target = File.join(target_dir, path)
    next if File.directory?(target)

    link = File.join(gem_dir, path)
    FileUtils.mkdir_p(File.dirname(link))
    File.symlink(target, link)
  end
end

def write_worker(dir, queue, marker)
  File.join(dir, 'worker.rb').tap do |worker|
    File.write(worker, <<~RUBY)
      class SymlinkedGemWorker
        include Shoryuken::Worker
        shoryuken_options queue: '#{queue}', auto_delete: true

        def perform(_sqs_msg, _body)
          File.write('#{marker}', [$LOADED_FEATURES.grep(%r{/shoryuken\\.rb\\z}).first, defined?(ActiveJob)].to_json)
        end
      end
    RUBY
  end
end

def write_job(dir)
  File.join(dir, 'job.rb').tap do |job|
    File.write(job, <<~RUBY)
      class SymlinkedGemJob < ActiveJob::Base
        def perform(marker)
          File.write(marker, [$LOADED_FEATURES.grep(%r{/shoryuken\\.rb\\z}).first, defined?(ActiveJob)].to_json)
        end
      end
    RUBY
  end
end

def run_until_processed(queue, required, marker, bin:, env:)
  run_shoryuken_until('-q', queue, '-r', required, '-c', '1', bin: bin, env: env) { File.exist?(marker) }
  JSON.parse(File.read(marker))
end

Bundler.with_unbundled_env do
  with_queue_and_dir do |queue, dir|
    gem_home = File.join(dir, 'gems')
    bin = install_gem(build_gem(dir), gem_home)
    gem_dir = Dir.glob(File.join(gem_home, 'gems', 'shoryuken-*')).first
    link_gem_files(gem_dir, File.join(dir, 'sandbox'))
    env = installed_gem_env(gem_home)

    Shoryuken::Client.queues(queue).send_message(message_body: 'symlinked')
    marker = File.join(dir, 'worker_marker')
    loaded, active_job = run_until_processed(queue, write_worker(dir, queue, marker), marker, bin: bin, env: env)
    assert_equal(File.join(gem_dir, 'lib', 'shoryuken.rb'), loaded)
    assert(File.symlink?(loaded), "#{loaded} must be a symlink")
    assert_equal(nil, active_job)

    marker = File.join(dir, 'job_marker')
    SymlinkedGemJob.set(queue: queue).perform_later(marker)
    # Loads Active Job before bin/shoryuken requires Shoryuken
    env = env.merge('RUBYOPT' => '-ractive_job')
    loaded, active_job = run_until_processed(queue, write_job(dir), marker, bin: bin, env: env)
    assert_equal(File.join(gem_dir, 'lib', 'shoryuken.rb'), loaded)
    assert_equal('constant', active_job)
  end
end
