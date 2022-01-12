# frozen_string_literal: true

RSpec.describe Faulty::Storage::CircuitProxy do
  let(:notifier) { Faulty::Events::Notifier.new }
  let(:circuit) { Faulty::Circuit.new('test') }
  let(:internal_circuit) { Faulty::Circuit.new('internal', sample_threshold: 2) }

  let(:failing_storage) do
    Class.new do
      def method_missing(*_args) # rubocop:disable Style/MethodMissingSuper
        raise 'fail'
      end

      def respond_to_missing?(*_args)
        true
      end
    end
  end

  it 'trips its internal circuit when storage fails repeatedly' do
    backend = failing_storage.new
    proxy = described_class.new(backend, notifier: notifier, circuit: internal_circuit)

    begin
      2.times { proxy.entry(circuit, Faulty.current_time, true) }
    rescue Faulty::CircuitFailureError
      nil
    end

    expect { proxy.entry(circuit, Faulty.current_time, true) }
      .to raise_error(Faulty::CircuitTrippedError)
  end

  it 'does not notify for circuit sucesses by default' do
    expect(notifier).not_to receive(:notify)
    backend = Faulty::Storage::Null.new
    proxy = described_class.new(backend, notifier: notifier)
    proxy.entry(circuit, Faulty.current_time, true, nil)
  end
end
