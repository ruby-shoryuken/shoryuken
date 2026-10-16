# frozen_string_literal: true

module Shoryuken
  # Contract layer: "dry-validation" like, but small and without dependencies. It allows for nested validations.
  #
  # Copied from karafka-core 2.6.5 (https://github.com/karafka/karafka-core, lib/karafka/core/contractable,
  # commit ac8e590). Copyright (c) Maciej Mensfeld, MIT License:
  #
  #   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
  #   documentation files (the "Software"), to deal in the Software without restriction, including without limitation
  #   the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
  #   permit persons to whom the Software is furnished to do so, subject to the following conditions:
  #
  #   The above copyright notice and this permission notice shall be included in all copies or substantial portions of
  #   the Software.
  #
  #   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
  #   THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  #   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
  #   CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
  #   IN THE SOFTWARE.
  #
  # Changes from the original: the Shoryuken namespace, and a class-level `error_messages` in place of the
  # `Karafka::Core::Configurable` setting.
  #
  # @note It is thread-safe to run but validations definitions should happen before threads are used.
  module Contractable
  end
end
