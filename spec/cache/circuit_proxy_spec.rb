# frozen_string_literal: true

RSpec.describe Faulty::Cache::CircuitProxy do
  let(:notifier) { Faulty::Events::Notifier.new }
  let(:circuit) { Faulty::Circuit.new('test', sample_threshold: 2) }

  let(:failing_cache) do
    Class.new do
      def method_missing(*_args)
        raise 'fail'
      end

      def respond_to_missing?(*_args)
        true
      end
    end
  end

  it 'trips its internal circuit when storage fails repeatedly' do
    backend = failing_cache.new
    proxy = described_class.new(backend, notifier: notifier, circuit: circuit)
    begin
      2.times { proxy.read('foo') }
    rescue Faulty::CircuitFailureError
      nil
    end

    expect { proxy.read('foo') }.to raise_error(Faulty::CircuitTrippedError)
  end

  it 'does not notify for circuit sucesses by default' do
    expect(notifier).not_to receive(:notify)
    backend = Faulty::Cache::Mock.new
    proxy = described_class.new(backend, notifier: notifier)
    proxy.read('foo')
  end

  it 'delegates fault_tolerant? directly' do
    backend = instance_double(Faulty::Cache::Mock)
    marker = Object.new
    allow(backend).to receive(:fault_tolerant?).and_return(marker)
    expect(described_class.new(backend, notifier: notifier).fault_tolerant?).to eq(marker)
  end
end
