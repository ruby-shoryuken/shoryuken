require 'spec_helper'
require 'shoryuken/cli'
require 'shoryuken/launcher'

RSpec.describe Shoryuken::CLI do
  let(:cli) { Shoryuken::CLI.instance }

  before(:each) do
    # make sure we do not bail
    allow(cli).to receive(:exit)

    # make sure we do not mess with standard streams
    allow_any_instance_of(IO).to receive(:reopen)
  end

  describe '#run' do
    let(:launcher) { instance_double('Shoryuken::Launcher') }

    before(:each) do
      allow(Shoryuken::Launcher).to receive(:new).and_return(launcher)
      allow(launcher).to receive(:run).and_raise(Interrupt)
      allow(launcher).to receive(:stop)
    end

    it 'does not raise' do
      expect { cli.run([]) }.to_not raise_error
    end

    it 'daemonizes with --daemon --logfile' do
      expect(cli).to receive(:celluloid_loaded?).and_return(false)
      expect(Process).to receive(:daemon)
      cli.run(['--daemon', '--logfile', '/dev/null'])
    end

    it 'does NOT daemonize with --daemon --logfile' do
      expect(Process).to_not receive(:daemon)
      cli.run(['--logfile', '/dev/null'])
    end

    it 'writes PID file with --pidfile' do
      pidfile = instance_double('File')
      expect(File).to receive(:open).with('/dev/null', 'w').and_yield(pidfile)
      expect(pidfile).to receive(:puts).with(Process.pid)
      cli.run(['--pidfile', '/dev/null'])
    end
  end

  describe '#daemonize' do
    before(:each) do
      allow(cli).to receive(:celluloid_loaded?).and_return(false)
    end

    it 'raises if logfile is not set' do
      expect { cli.send(:daemonize, daemon: true) }.to raise_error(ArgumentError)
    end

    it 'raises if Celluloid is already loaded' do
      expect(cli).to receive(:celluloid_loaded?).and_return(true)
      args = { daemon: true, logfile: '/dev/null' }
      expect{ cli.send(:daemonize, args) }.to raise_error(RuntimeError)
    end

    it 'calls Process.daemon' do
      args = { daemon: true, logfile: '/dev/null' }
      expect(Process).to receive(:daemon).with(true, true)
      cli.send(:daemonize, args)
    end
  end
end
