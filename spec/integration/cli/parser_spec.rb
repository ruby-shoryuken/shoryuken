# frozen_string_literal: true

# This spec tests the command dispatcher and option parser of the `shoryuken` CLI (`bin/cli/base.rb`) in-process.
#
# Options parse as Thor parsed them: numeric values become an Integer or a Float, an array or hash option takes the
# values up to the next switch, a boolean takes `--no-` and `--skip-`, underscores in a long switch are dashes and
# defaults apply. Commands match by a unique prefix. Bad input prints Thor's error message and exits with status 1.
#
# Lives under spec/integration (not spec/lib) because requiring bin/cli defines Shoryuken::CLI, and
# Shoryuken#server? is `defined?(Shoryuken::CLI)`.

require 'stringio'
require_relative '../../../bin/cli/base'

class ParserSpecCli < Shoryuken::CLI::Base
  namespace :spec

  class << self
    def results
      @results ||= []
    end
  end

  class_option :endpoint, aliases: '-e', type: :string, default: 'http://default', desc: 'Endpoint URL'

  desc 'record NAME [EXTRA]', 'Records its options'
  method_option :count,       aliases: '-c', type: :numeric,                 desc: 'a number'
  method_option :names,       aliases: '-n', type: :array,                   desc: 'names'
  method_option :attributes,  aliases: '-a', type: :hash,    default: {},    desc: 'attributes'
  method_option :flag,        aliases: '-f', type: :boolean, default: true,  desc: 'a flag'
  method_option :config_file,                type: :string,                  desc: 'a path'
  def record(name, extra = nil)
    options[:attributes]['mutated'] = 'yes' if extra == 'mutate'
    self.class.results << [options, name, extra]
  end

  desc 'reset', 'Does nothing'
  def reset; end
end

class TtyIO < StringIO
  def tty?
    true
  end
end

def colored(env)
  saved = ENV.to_h.slice('NO_COLOR', 'TERM')
  ENV.update('NO_COLOR' => nil, 'TERM' => 'xterm').update(env)
  $stdout = TtyIO.new
  ParserSpecCli.new.say('text', :red)
  $stdout.string
ensure
  $stdout = STDOUT
  ENV.update('NO_COLOR' => nil, 'TERM' => nil).update(saved)
end

def cli(*argv)
  out = StringIO.new
  stdout = $stdout
  stderr = $stderr
  $stdout = $stderr = out
  status = 0

  begin
    ParserSpecCli.start(argv)
  rescue SystemExit => e
    status = e.status
  end

  [status, out.string]
ensure
  $stdout = stdout
  $stderr = stderr
end

def recorded(*argv)
  ParserSpecCli.results.clear
  status, output = cli(*argv)
  assert_equal(0, status, output)
  ParserSpecCli.results.last
end

def assert_fails(argv, message)
  status, output = cli(*argv)
  assert_equal(1, status, "#{argv.inspect} must exit with status 1, got: #{output}")
  assert_includes(output, message, "got: #{output}")
end

# --- defaults ---
options, name, extra = recorded('record', 'q')
assert_equal({ endpoint: 'http://default', attributes: {}, flag: true }, options)
assert_equal(['q', nil], [name, extra])
assert_equal({ 'mutated' => 'yes' }, recorded('record', 'q', 'mutate').first[:attributes])
assert_equal({}, recorded('record', 'q').first[:attributes], 'a default must not keep changes')

# --- numeric ---
assert_equal(3, recorded('record', 'q', '-c', '3').first[:count])
assert_equal(1.5, recorded('record', 'q', '--count=1.5').first[:count])
assert_equal(4, recorded('record', 'q', '-c=4').first[:count])
assert_equal(-1, recorded('record', 'q', '--count', '-1').first[:count])
assert_equal(3, recorded('record', 'q', '-c3').first[:count])
assert_equal(nil, recorded('record', 'q', '-c', '3', '--no-count').first[:count])

# --- array ---
options, name = recorded('record', 'q', '-n', 'a,1', 'b', '-c', '2')
assert_equal([%w[a,1 b], 2, 'q'], [options[:names], options[:count], name])
assert_equal(%w[a b], recorded('record', 'q', '--names=a', 'b').first[:names])
assert_equal(%w[b], recorded('record', 'q', '-n', 'a', '-n', 'b').first[:names], 'the last array option must win')
options, name = recorded('record', 'q', '-fn', 'a', 'b')
assert_equal([true, %w[a b], 'q'], [options[:flag], options[:names], name], 'a cluster must end with the array switch')
options, name = recorded('record', '--no-flag', '-n', 'a', '--', 'q')
assert_equal([false, %w[a], 'q'], [options[:flag], options[:names], name])

# --- hash ---
options, name, extra = recorded('record', 'q', '-a', 'k:v', 'x:y:z', 'extra')
assert_equal([{ 'k' => 'v', 'x' => 'y:z' }, 'q', 'extra'], [options[:attributes], name, extra])
options, name, extra = recorded('record', 'q', '-a', 'k')
assert_equal([{}, 'q', 'k'], [options[:attributes], name, extra], 'a hash option must take only key:value')
assert_equal({ 'k' => 'v' }, recorded('record', 'q', '-fa', 'k:v').first[:attributes])

# --- boolean ---
assert_equal(true, recorded('record', 'q', '-f').first[:flag])
assert_equal(false, recorded('record', 'q', '--no-flag').first[:flag])
assert_equal(false, recorded('record', 'q', '--skip-flag').first[:flag])
assert_equal(false, recorded('record', 'q', '--flag=false').first[:flag])
assert_equal(false, recorded('record', 'q', '-f=false').first[:flag])
assert_equal(true, recorded('record', 'q', '--no-flag', '--flag=true').first[:flag])
options, name = recorded('record', '-f', 'false', 'q')
assert_equal([false, 'q'], [options[:flag], name])
options, name = recorded('record', '--flag', 'q')
assert_equal([true, 'q'], [options[:flag], name])
assert_equal(true, recorded('record', 'q', '--no-flag=true').first[:flag])
options, name, extra = recorded('record', 'q', '--flag=maybe')
assert_equal([true, 'q', 'maybe'], [options[:flag], name, extra])

# --- strings, switch spelling, order ---
assert_equal('a', recorded('record', 'q', '--config-file', 'a').first[:config_file])
assert_equal('b', recorded('record', 'q', '--config_file=b').first[:config_file])
assert_equal('http://x', recorded('record', '-e', 'http://x', 'q').first[:endpoint])
assert_equal(%w[-c q], recorded('record', '--', '-c', 'q')[1..])
assert_equal('-h', recorded('record', '--', '-h')[1], 'a -h after -- must be an argument')

# --- a string option with no value takes its default or its name, never the next switch ---
options, name = recorded('record', 'q', '--config-file', '-f')
assert_equal(['config_file', true, 'q'], [options[:config_file], options[:flag], name])
assert_equal('config_file', recorded('record', 'q', '--config-file').first[:config_file])
assert_equal('http://default', recorded('record', 'q', '-e', '-f').first[:endpoint])
assert_equal(nil, recorded('record', 'q', '--no-config-file').first[:config_file])

# --- commands ---
assert_equal('q', recorded('rec', 'q')[1], 'a unique prefix must run the command')
assert_fails(%w[re], 'Ambiguous command re matches [record, reset]')
assert_fails(%w[bogus], 'Could not find command "bogus".')
assert_fails(%w[recrod q], %(Could not find command "recrod".\nDid you mean?  "record"))

# --- bad options and arguments ---
assert_fails(%w[record q -x --bogus=1 -y], 'Unknown switches "-x", "--bogus=1", "-y"')
assert_fails(%w[record q --cou 2], 'Unknown switches "--cou"')
assert_fails(%w[record q --conut 2], %(Unknown switches "--conut"\nDid you mean?  "--count"))
assert_fails(%w[record q -na], "No value provided for option '--names'")
assert_fails(%w[record q -xy], 'Unknown switches "-xy"')
assert_fails(%w[record q -nfoo,1], 'Unknown switches "-nfoo,1"')
assert_fails(%w[record q -ak:v], 'Unknown switches "-ak:v"')
assert_fails(%w[record q -n -1], 'Unknown switches "-1"')
assert_fails(%w[record q -n -f], "No value provided for option '--names'")
assert_fails(%w[record q -a], "No value provided for option '--attributes'")
assert_fails(%w[record q -a -f], "No value provided for option '--attributes'")
assert_fails(%w[record q -c -f], "No value provided for option '--count'")
assert_fails(%w[record q -c abc], %(Expected numeric value for '--count'; got "abc"))
assert_fails(%w[record q -c], "No value provided for option '--count'")
assert_fails(%w[record q -n], "No value provided for option '--names'")
assert_fails(
  %w[record],
  %(ERROR: "shoryuken spec record" was called with no arguments\nUsage: "shoryuken spec record NAME [EXTRA]")
)
assert_fails(%w[record a b c], 'ERROR: "shoryuken spec record" was called with arguments ["a", "b", "c"]')

# --- help ---
[[], %w[-h], %w[--help], %w[help], %w[help -h]].each do |argv|
  status, output = cli(*argv)
  assert_equal(0, status, output)
  assert_includes(output, "Commands:\n  shoryuken spec help [COMMAND]       # Describe subcommands or one")
  assert_includes(output, 'shoryuken spec record NAME [EXTRA]  # Records its options')
  assert_includes(output, "Options:\n  -e, --endpoint=ENDPOINT  # Endpoint URL")
end

[%w[help record], %w[help rec], %w[record -h], %w[record q --help]].each do |argv|
  status, output = cli(*argv)
  assert_equal(0, status, output)
  assert_includes(output, "Usage:\n  shoryuken spec record NAME [EXTRA]\n")
  assert_includes(output, '-n, --names=one two three')
  assert_includes(output, '-a, --attributes=key:value')
  assert_includes(output, '-f, --[no-]flag')
  assert_includes(output, "                         # Default: true\n")
  assert_includes(output, '    --config-file=CONFIG_FILE')
  assert_includes(output, "\nRecords its options\n")
  assert_equal([], ParserSpecCli.results.clear, 'help must not run the command')
end

status, output = cli('help', 'help')
assert_equal(0, status, output)
assert_includes(output, 'shoryuken spec help [COMMAND]')

# --- say ---
status, output = cli('reset')
assert_equal([0, ''], [status, output])
out = StringIO.new
$stdout = out
ParserSpecCli.new.say('plain', :red)
$stdout = STDOUT
assert_equal("plain\n", out.string, 'say must not color output that is not a terminal')
assert_equal("\e[31mtext\e[0m\n", colored({}))
assert_equal("text\n", colored('NO_COLOR' => '1'), 'NO_COLOR must turn colors off')
assert_equal("text\n", colored('TERM' => 'dumb'), 'a dumb terminal must get no colors')
