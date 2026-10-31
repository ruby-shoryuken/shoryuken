# frozen_string_literal: true

RSpec.describe Shoryuken::Runner do
  let(:cli) { Shoryuken::Runner.instance }

  before do
    # make sure we do not bail
    allow(cli).to receive(:exit)

    # make sure we do not mess with standard streams
    allow_any_instance_of(IO).to receive(:reopen)
  end

  describe '#run' do
    let(:launcher) { instance_double('Shoryuken::Launcher') }

    before do
      allow(Shoryuken::Launcher).to receive(:new).and_return(launcher)
      allow(launcher).to receive(:start).and_raise(Interrupt)
      allow(launcher).to receive(:stop!)
    end

    it 'does not raise' do
      expect { cli.run({}) }.to_not raise_error
    end

    it 'daemonizes with --daemon --logfile' do
      expect(Process).to receive(:daemon)
      cli.run(daemon: true, logfile: '/dev/null')
    end

    it 'does NOT daemonize with --logfile' do
      expect(Process).to_not receive(:daemon)
      cli.run(logfile: '/dev/null')
    end

    it 'writes PID file with --pidfile' do
      pidfile = instance_double('File')
      expect(File).to receive(:open).with('/dev/null', 'w').and_yield(pidfile)
      expect(pidfile).to receive(:puts).with(Process.pid)
      cli.run(pidfile: '/dev/null')
    end

    context 'when USR1 arrives' do
      before do
        allow(launcher).to receive(:start) { Process.kill('USR1', Process.pid) }
        allow(launcher).to receive(:stop)
        allow(cli).to receive(:exit).and_raise(SystemExit)
      end

      it 'exits with status 0 after a soft shutdown' do
        allow(launcher).to receive(:failed?).and_return(false)

        expect { cli.run({}) }.to raise_error(SystemExit)
        expect(launcher).to have_received(:stop)
        expect(cli).to have_received(:exit).with(0)
      end

      it 'exits with status 1 when a fatal dispatch error caused the shutdown' do
        allow(launcher).to receive(:failed?).and_return(true)

        expect { cli.run({}) }.to raise_error(SystemExit)
        expect(launcher).to have_received(:stop)
        expect(cli).to have_received(:exit).with(1)
      end
    end
  end

  describe '#daemonize' do
    it 'calls Process.daemon' do
      args = { daemon: true, logfile: '/dev/null' }
      expect(Process).to receive(:daemon).with(true, true)
      cli.send(:daemonize, args)
    end
  end
end
