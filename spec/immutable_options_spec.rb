# frozen_string_literal: true

RSpec.describe Faulty::ImmutableOptions do
  let(:example_class) do
    Struct.new(:name, :cache, :storage) do
      include Faulty::ImmutableOptions

      private

      def defaults
        { cache: 'default_cache' }
      end

      def required
        %i[name]
      end

      def finalize
        self.storage = 'finalized'
      end
    end
  end

  it 'applies a default if an option is not present' do
    opts = example_class.new(name: 'foo')
    expect(opts.cache).to eq('default_cache')
  end

  it 'overrides defaults with given hash' do
    opts = example_class.new(name: 'foo', cache: 'special_cache')
    expect(opts.cache).to eq('special_cache')
  end

  it 'overrides defaults with block' do
    opts = example_class.new(name: 'foo') { |o| o.cache = 'special_cache' }
    expect(opts.cache).to eq('special_cache')
  end

  it 'calls finalize after options are set' do
    opts = example_class.new(name: 'foo', storage: 'from_hash') { |o| o.storage = 'from_block' }
    expect(opts.storage).to eq('finalized')
  end

  it 'raises error if required option is missing' do
    expect { example_class.new({}) }.to raise_error(ArgumentError, /Missing required attribute name/)
  end

  it 'raises error if required option is nil' do
    expect { example_class.new(name: nil) }.to raise_error(ArgumentError, /Missing required attribute name/)
  end

  it 'freezes options after initialization' do
    opts = example_class.new(name: 'foo')
    expect { opts.name = 'bar' }.to raise_error(FrozenError)
  end
end
