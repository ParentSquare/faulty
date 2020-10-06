# frozen_string_literal: true

RSpec.describe Faulty::Cache::FaultTolerantProxy do
  let(:notifier) { Faulty::Events::Notifier.new }

  let(:failing_cache) do
    Class.new do
      def method_missing(*_args) # rubocop:disable Style/MethodMissingSuper
        raise 'fail'
      end

      def respond_to_missing?(*_args)
        true
      end
    end
  end

  let(:fake_cache) do
    Class.new do
      def method_missing(*_args) # rubocop:disable Style/MethodMissingSuper
        'fake'
      end

      def respond_to_missing?(*_args)
        true
      end
    end
  end

  it 'delegates to backend when reading succeeds' do
    value = described_class.new(fake_cache.new, notifier: notifier).read('foo')
    expect(value).to eq('fake')
  end

  it 'returns nil when reading fails' do
    backend = failing_cache.new
    result = described_class.new(backend, notifier: notifier).read('foo')
    expect(result).to eq(nil)
  end
end
