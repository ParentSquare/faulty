# frozen_string_literal: true

RSpec.describe Faulty::Cache::FaultTolerantProxy do
  let(:notifier) { Faulty::Events::Notifier.new }

  let(:failing_cache_class) do
    Class.new do
      def method_missing(*_args)
        raise 'fail'
      end

      def respond_to_missing?(*_args)
        true
      end
    end
  end

  let(:failing_cache) do
    failing_cache_class.new
  end

  let(:mock_cache) { Faulty::Cache::Mock.new }

  it 'delegates to backend when reading succeeds' do
    mock_cache.write('foo', 'val')
    value = described_class.new(mock_cache, notifier: notifier).read('foo')
    expect(value).to eq('val')
  end

  it 'returns nil when reading fails' do
    expect(notifier).to receive(:notify)
      .with(:cache_failure, key: 'foo', action: :read, error: instance_of(RuntimeError))
    result = described_class.new(failing_cache, notifier: notifier).read('foo')
    expect(result).to be_nil
  end

  it 'delegates to backend when writing succeeds' do
    described_class.new(mock_cache, notifier: notifier).write('foo', 'val')
    expect(mock_cache.read('foo')).to eq('val')
  end

  it 'skips writing when backend fails' do
    expect(notifier).to receive(:notify)
      .with(:cache_failure, key: 'foo', action: :write, error: instance_of(RuntimeError))
    proxy = described_class.new(failing_cache, notifier: notifier)
    proxy.write('foo', 'val')
  end

  it 'is always fault tolerant' do
    expect(described_class.new(Object.new, notifier: notifier)).to be_fault_tolerant
  end

  describe '.wrap' do
    it 'returns fault-tolerant cache unmodified' do
      expect(described_class.wrap(mock_cache, notifier: notifier)).to eq(mock_cache)
    end

    it 'wraps fault-tolerant cache' do
      expect(described_class.wrap(Faulty::Cache::Rails.new(nil), notifier: notifier))
        .to be_a(described_class)
    end
  end
end
