# frozen_string_literal: true

# Builds and installs the gem as users get it, for specs that run it from outside the repo
module PackagingHelper
  REPO_ROOT = File.expand_path('../..', __dir__)

  # Builds the gem from the gemspec into the directory, returns the path of the .gem file
  def build_gem(dir)
    gem_file = File.join(dir, 'shoryuken.gem')
    output, status = Open3.capture2e('gem', 'build', 'shoryuken.gemspec', '-o', gem_file, chdir: REPO_ROOT)
    assert(status.success?, "gem build failed: #{output}")
    gem_file
  end

  # Installs the .gem file into the gem home without its dependencies, returns the path of its shoryuken executable
  def install_gem(gem_file, gem_home)
    output, status = Open3.capture2e(
      'gem', 'install', gem_file, '--local', '--ignore-dependencies', '--no-document',
      '--install-dir', gem_home, '--bindir', File.join(gem_home, 'bin')
    )
    assert(status.success?, "gem install failed: #{output}")
    File.join(gem_home, 'bin', 'shoryuken')
  end

  # Environment that runs the gem installed in the gem home, with its dependencies from the current gem path
  def installed_gem_env(gem_home)
    { 'GEM_HOME' => gem_home, 'GEM_PATH' => [gem_home, *Gem.path].join(File::PATH_SEPARATOR) }
  end
end
