# frozen_string_literal: true

RSpec.describe RuboCop::Cop::Shoryuken::MultilineCallParentheses, :config do
  it 'registers and corrects several arguments spanning lines' do
    expect_offense(<<~RUBY)
      attr_accessor :foo, :bar,
      ^^^^^^^^^^^^^ Use parentheses for a call whose arguments span several lines.
        :baz
    RUBY

    expect_correction(<<~RUBY)
      attr_accessor(:foo, :bar,
        :baz)
    RUBY
  end

  it 'registers and corrects a braceless hash with several keys spanning lines' do
    expect_offense(<<~RUBY)
      shoryuken_options queue: 'a',
      ^^^^^^^^^^^^^^^^^ Use parentheses for a call whose arguments span several lines.
        auto_delete: true
    RUBY

    expect_correction(<<~RUBY)
      shoryuken_options(queue: 'a',
        auto_delete: true)
    RUBY
  end

  it 'registers and corrects a call with a receiver and safe navigation' do
    expect_offense(<<~RUBY)
      options&.extract! :a,
               ^^^^^^^^ Use parentheses for a call whose arguments span several lines.
        :b
    RUBY

    expect_correction(<<~RUBY)
      options&.extract!(:a,
        :b)
    RUBY
  end

  it 'keeps a do block outside the parentheses' do
    expect_offense(<<~RUBY)
      it 'works',
      ^^ Use parentheses for a call whose arguments span several lines.
        :slow do
        run
      end
    RUBY

    expect_correction(<<~RUBY)
      it('works',
        :slow) do
        run
      end
    RUBY
  end

  it 'keeps a trailing comment outside the parentheses' do
    expect_offense(<<~RUBY)
      raise Error,
      ^^^^^ Use parentheses for a call whose arguments span several lines.
        'message' # why
    RUBY

    expect_correction(<<~RUBY)
      raise(Error,
        'message') # why
    RUBY
  end

  it 'keeps a modifier outside the parentheses' do
    expect_offense(<<~RUBY)
      raise Error,
      ^^^^^ Use parentheses for a call whose arguments span several lines.
        'message' if failed
    RUBY

    expect_correction(<<~RUBY)
      raise(Error,
        'message') if failed
    RUBY
  end

  it 'wraps a block-pass and a double splat' do
    expect_offense(<<~RUBY)
      call_it :a,
      ^^^^^^^ Use parentheses for a call whose arguments span several lines.
        **opts, &blk
    RUBY

    expect_correction(<<~RUBY)
      call_it(:a,
        **opts, &blk)
    RUBY
  end

  it 'closes after a heredoc opener when the heredoc is the last argument' do
    expect_offense(<<~RUBY)
      write :a,
      ^^^^^ Use parentheses for a call whose arguments span several lines.
        <<~TXT
          text
        TXT
    RUBY

    expect_correction(<<~RUBY)
      write(:a,
        <<~TXT)
          text
        TXT
    RUBY
  end

  it 'accepts a heredoc whose opener is on the call line' do
    expect_no_offenses(<<~RUBY)
      raise Error, <<~MSG
        text
      MSG
    RUBY
  end

  it 'accepts a single argument that spans lines' do
    expect_no_offenses(<<~RUBY)
      expect(queue).to receive(:send_message).with(
        a: 1
      )
    RUBY
  end

  it 'accepts a braceless hash with one key that spans lines' do
    expect_no_offenses(<<~RUBY)
      configure key: [
        1
      ]
    RUBY
  end

  it 'accepts arguments on one line' do
    expect_no_offenses(<<~RUBY)
      puts a, b
    RUBY
  end

  it 'accepts parenthesized calls' do
    expect_no_offenses(<<~RUBY)
      foo(:a,
          :b)
    RUBY
  end

  it 'accepts an index setter whose arguments span lines' do
    expect_no_offenses(<<~RUBY)
      foo[:a,
          :b] = 1
    RUBY
  end
end
