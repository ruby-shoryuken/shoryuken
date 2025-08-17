# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoryuken::Helpers::StringUtils do
  describe '.constantize' do
    it 'returns a simple constant' do
      expect(described_class.constantize('Object')).to eq(Object)
      expect(described_class.constantize('String')).to eq(String)
      expect(described_class.constantize('Hash')).to eq(Hash)
    end

    it 'returns nested constants' do
      expect(described_class.constantize('Shoryuken::Helpers::StringUtils')).to eq(Shoryuken::Helpers::StringUtils)
      expect(described_class.constantize('Shoryuken::Helpers::AtomicCounter')).to eq(Shoryuken::Helpers::AtomicCounter)
    end

    it 'handles leading double colon' do
      expect(described_class.constantize('::Object')).to eq(Object)
      expect(described_class.constantize('::String')).to eq(String)
      expect(described_class.constantize('::Shoryuken::Helpers::StringUtils')).to eq(Shoryuken::Helpers::StringUtils)
    end

    it 'handles empty string' do
      expect(described_class.constantize('')).to eq(Object)
    end

    it 'handles string with only double colons' do
      expect(described_class.constantize('::')).to eq(Object)
      expect(described_class.constantize('::::')).to eq(Object)
    end

    it 'raises NameError for non-existent constants' do
      expect { described_class.constantize('NonExistentClass') }.to raise_error(NameError)
      expect { described_class.constantize('Shoryuken::NonExistentClass') }.to raise_error(NameError)
      expect { described_class.constantize('NonExistent::AlsoNonExistent') }.to raise_error(NameError)
    end

    it 'raises NameError for partially invalid nested constants' do
      expect { described_class.constantize('Shoryuken::NonExistent::AlsoNonExistent') }.to raise_error(NameError)
    end

    context 'with dynamically defined constants' do
      before do
        # Define a temporary constant for testing
        Object.const_set('TempTestClass', Class.new)
        TempTestClass.const_set('NestedClass', Class.new)
      end

      after do
        # Clean up the temporary constant
        Object.send(:remove_const, 'TempTestClass') if Object.const_defined?('TempTestClass')
      end

      it 'finds dynamically defined constants' do
        expect(described_class.constantize('TempTestClass')).to eq(TempTestClass)
      end

      it 'finds nested dynamically defined constants' do
        expect(described_class.constantize('TempTestClass::NestedClass')).to eq(TempTestClass::NestedClass)
      end
    end

    context 'with module constants' do
      it 'returns module constants' do
        expect(described_class.constantize('Shoryuken')).to eq(Shoryuken)
        expect(described_class.constantize('Shoryuken::Helpers')).to eq(Shoryuken::Helpers)
      end
    end

    context 'with worker class scenarios' do
      before do
        # Simulate typical worker class scenarios
        unless Object.const_defined?('MyApp')
          Object.const_set('MyApp', Module.new)
        end
        
        unless MyApp.const_defined?('EmailWorker')
          MyApp.const_set('EmailWorker', Class.new)
        end
      end

      after do
        # Clean up
        MyApp.send(:remove_const, 'EmailWorker') if MyApp.const_defined?('EmailWorker')
        Object.send(:remove_const, 'MyApp') if Object.const_defined?('MyApp')
      end

      it 'loads worker classes from string names' do
        worker_class = described_class.constantize('MyApp::EmailWorker')
        expect(worker_class).to eq(MyApp::EmailWorker)
        expect(worker_class.new).to be_an_instance_of(MyApp::EmailWorker)
      end
    end

    context 'edge cases' do
      it 'handles constants with numbers' do
        # Using existing constants that might have numbers
        expect(described_class.constantize('Encoding::UTF_8')).to eq(Encoding::UTF_8)
      end

      it 'is case sensitive' do
        expect { described_class.constantize('object') }.to raise_error(NameError)
        expect { described_class.constantize('STRING') }.to raise_error(NameError)
      end

      it 'handles single character constant names' do
        # Define a single character constant for testing
        Object.const_set('A', Class.new) unless Object.const_defined?('A')
        
        expect(described_class.constantize('A')).to eq(A)
        
        # Clean up
        Object.send(:remove_const, 'A') if Object.const_defined?('A')
      end
    end

    context 'error messages' do
      it 'provides meaningful error messages' do
        expect { described_class.constantize('NonExistent') }.to raise_error(NameError, /NonExistent/)
      end
    end
  end
end