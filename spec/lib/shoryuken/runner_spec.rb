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

    it 'does not daemonize when the options ask to daemonize without a logfile' do
      expect(Process).not_to receive(:daemon)

      expect { cli.run(daemon: true) }
        .to raise_error(Shoryuken::Errors::InvalidConfigurationError, /You should set a logfile/)
    end

    it 'does not daemonize when a queue does not exist and there is nothing to require' do
      allow(Shoryuken::Client)
        .to receive(:queues)
        .with('missing')
        .and_raise(Aws::SQS::Errors::NonExistentQueue.new(nil, nil))
      expect(Process).not_to receive(:daemon)

      expect { cli.run(daemon: true, logfile: '/dev/null', queues: ['missing']) }
        .to raise_error(Shoryuken::Errors::QueueNotFoundError)
    end

    it 'requires the files after it daemonizes' do
      events = []
      allow(Process).to receive(:daemon) { events << :daemon }
      allow_any_instance_of(Shoryuken::EnvironmentLoader).to receive(:load) { events << :load }

      cli.run(daemon: true, logfile: '/dev/null', require: './workers')

      expect(events).to eq(%i[daemon load])
    end

    context 'with a pidfile' do
      let(:dir) { Dir.mktmpdir }
      let(:pidfile) { File.join(dir, 'shoryuken.pid') }

      after { FileUtils.rm_rf(dir) }

      it 'removes the pidfile at exit when it holds the pid of this process' do
        allow(cli).to receive(:at_exit) { |&block| block.call }

        cli.run(pidfile: pidfile)

        expect(File.exist?(pidfile)).to be(false)
      end

      it 'keeps the pidfile at exit when another process wrote its pid to it' do
        allow(cli).to receive(:at_exit) { |&block| File.write(pidfile, "#{Process.pid + 1}\n") && block.call }

        cli.run(pidfile: pidfile)

        expect(File.read(pidfile)).to eq("#{Process.pid + 1}\n")
      end
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

    context 'when USR1 arrives after the graceful stop of a TSTP has ended' do
      before do
        allow(launcher).to receive(:start) { Process.kill('TSTP', Process.pid) }
        allow(launcher).to receive(:stop) do
          graceful = Thread.current
          Thread.new do
            graceful.join
            Process.kill('USR1', Process.pid)
          end
        end
        allow(launcher).to receive(:failed?).and_return(false)
        allow(cli).to receive(:exit).and_raise(SystemExit)
      end

      it 'exits with status 0' do
        Timeout.timeout(5) { expect { cli.run({}) }.to raise_error(SystemExit) }
        expect(launcher).to have_received(:stop).once
        expect(cli).to have_received(:exit).with(0)
      end
    end

    context 'when the graceful stop of a TSTP raises' do
      before do
        allow(launcher).to receive(:start) { Process.kill('TSTP', Process.pid) }
        allow(launcher).to receive(:stop).and_raise('stop failure')
      end

      it 'raises the error on the main thread' do
        Timeout.timeout(5) { expect { cli.run({}) }.to raise_error(RuntimeError, 'stop failure') }
      end
    end

    context 'when TERM arrives during the graceful stop of a TSTP' do
      let(:release) { Queue.new }

      before do
        allow(launcher).to receive(:start) { Process.kill('TSTP', Process.pid) }
        allow(launcher).to receive(:stop) do
          Process.kill('TERM', Process.pid)
          release.pop
        end
      end

      after { release.close }

      it 'stops at once without waiting for the graceful stop' do
        expect { cli.run({}) }.to_not raise_error
        expect(launcher).to have_received(:stop!)
        expect(cli).to have_received(:exit).with(0)
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
