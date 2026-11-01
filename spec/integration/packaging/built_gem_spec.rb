# frozen_string_literal: true

# This spec tests the gem as users install it: built from the gemspec,
# installed into an empty gem home and run from there, not from the repo.
#
# The gem ships only lib/, bin/shoryuken, bin/cli/,
# config/locales/, README.md, CHANGELOG.md and LICENSE, and the installed
# gem still runs: `shoryuken version`, `shoryuken sqs`, `shoryuken start`
# processing a message, and a config error message read from
# config/locales/errors.yml.

require 'rubygems/package'

setup_sqs

ROOT = File.expand_path('../../..', __dir__)

def build_gem(dir)
  gem_file = File.join(dir, 'shoryuken.gem')
  output, status = Open3.capture2e('gem', 'build', 'shoryuken.gemspec', '-o', gem_file, chdir: ROOT)
  assert(status.success?, "gem build failed: #{output}")
  gem_file
end

def install_gem(gem_file, gem_home)
  output, status = Open3.capture2e(
    'gem', 'install', gem_file, '--local', '--ignore-dependencies', '--no-document',
    '--install-dir', gem_home, '--bindir', File.join(gem_home, 'bin')
  )
  assert(status.success?, "gem install failed: #{output}")
  File.join(gem_home, 'bin', 'shoryuken')
end

def expected_files
  tracked, status = Open3.capture2(
    'git', 'ls-files', 'lib', 'bin/cli', 'config/locales', 'bin/shoryuken', 'README.md', 'CHANGELOG.md', 'LICENSE',
    chdir: ROOT
  )
  assert(status.success?, 'git ls-files failed')
  tracked.split("\n").sort
end

def write_worker(dir, queue, marker)
  File.join(dir, 'worker.rb').tap do |worker|
    File.write(worker, <<~RUBY)
      class PackagedGemWorker
        include Shoryuken::Worker
        shoryuken_options queue: '#{queue}', auto_delete: true

        def perform(_sqs_msg, _body)
          File.write('#{marker}', Gem.loaded_specs['shoryuken'].full_gem_path)
        end
      end
    RUBY
  end
end

Bundler.with_unbundled_env do
  with_queue_and_dir do |queue, dir|
    gem_file = build_gem(dir)
    files = Gem::Package.new(gem_file).spec.files
    assert_equal(expected_files, files.sort)

    gem_home = File.join(dir, 'gems')
    bin = install_gem(gem_file, gem_home)
    env = { 'GEM_HOME' => gem_home, 'GEM_PATH' => [gem_home, *Gem.path].join(File::PATH_SEPARATOR) }

    status, output = run_shoryuken_command_until_exit('version', bin: bin, env: env)
    assert(status.success?, output)
    assert_includes(output, Shoryuken::VERSION)

    status, output = run_shoryuken_sqs('ls', queue, bin: bin, env: env)
    assert(status.success?, output)
    assert_includes(output, queue)

    Shoryuken::Client.queues(queue).send_message(message_body: 'packaged')
    marker = File.join(dir, 'gem_dir')
    worker = write_worker(dir, queue, marker)
    run_shoryuken_until('-q', queue, '-r', worker, '-c', '1', bin: bin, env: env) { File.exist?(marker) }
    assert(File.read(marker).start_with?(gem_home), File.read(marker))

    config = File.join(dir, 'invalid.yml')
    File.write(config, "concurrency: -1\n")
    status, output = run_shoryuken_until_exit('-C', config, '-r', worker, bin: bin, env: env)
    refute(status.success?)
    assert_includes(output, 'needs to be an Integer greater than 0')
  end
end
