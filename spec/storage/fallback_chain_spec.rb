# frozen_string_literal: true

RSpec.describe Faulty::Storage::FallbackChain do
  let(:failing_class) do
    Class.new do
      def method_missing(_method, *_args) # rubocop:disable Style/MethodMissingSuper
        raise 'fail'
      end

      def respond_to_missing?(_method, _include_all = false)
        true
      end
    end
  end

  let(:failing) { failing_class.new }
  let(:memory) { Faulty::Storage::Memory.new }
  let(:memory2) { Faulty::Storage::Memory.new }
  let(:notifier) { Faulty::Events::Notifier.new }
  let(:circuit) { Faulty::Circuit.new('test') }
  let(:init_status) { Faulty::Status.new(options: circuit.options) }
  let(:succeeding_chain) { described_class.new([memory, memory2], notifier: notifier) }
  let(:partially_failing_chain) { described_class.new([failing, memory], notifier: notifier) }
  let(:midway_failure_chain) { described_class.new([memory, failing, memory2], notifier: notifier) }
  let(:long_chain) { described_class.new([failing, failing_class.new, memory], notifier: notifier) }
  let(:failing_chain) { described_class.new([failing, failing_class.new], notifier: notifier) }

  context 'with #entry' do
    it 'calls only first storage when successful' do
      status = succeeding_chain.entry(circuit, Faulty.current_time, false, init_status)
      expect(status.sample_size).to eq(1)
      expect(memory.history(circuit).size).to eq(1)
      expect(memory2.history(circuit).size).to eq(0)
    end

    it 'falls back to next storage after failure' do
      expect(notifier).to receive(:notify)
        .with(:storage_failure, circuit: circuit, action: :entry, error: be_a(RuntimeError))
      status = partially_failing_chain.entry(circuit, Faulty.current_time, false, init_status)
      expect(status.sample_size).to eq(1)
      expect(memory.history(circuit).size).to eq(1)

      expect(notifier).to receive(:notify)
        .with(:storage_failure, circuit: circuit, action: :history, error: be_a(RuntimeError))
      expect(partially_failing_chain.history(circuit).size).to eq(1)
    end

    it 'chains fallbacks for multiple failures' do
      expect(notifier).to receive(:notify)
        .with(:storage_failure, circuit: circuit, action: :entry, error: be_a(RuntimeError))
        .twice
      status = long_chain.entry(circuit, Faulty.current_time, false, init_status)
      expect(status.sample_size).to eq(1)
      expect(memory.history(circuit).size).to eq(1)

      expect(notifier).to receive(:notify)
        .with(:storage_failure, circuit: circuit, action: :history, error: be_a(RuntimeError))
        .twice
      expect(long_chain.history(circuit).size).to eq(1)
    end

    it 'raises error if all storages fail' do
      expect do
        failing_chain.entry(circuit, Faulty.current_time, true, nil)
      end.to raise_error(
        Faulty::AllFailedError,
        'Faulty::Storage::FallbackChain#entry failed for all storage backends: fail, fail'
      )
    end
  end

  context 'with #lock' do
    it 'delegates to all when successful' do
      succeeding_chain.lock(circuit, :open)
      expect(memory.status(circuit).locked_open?).to eq(true)
      expect(memory2.status(circuit).locked_open?).to eq(true)
    end

    it 'continues delegating after failure and raises' do
      expect do
        midway_failure_chain.lock(circuit, :open)
      end.to raise_error(
        Faulty::PartialFailureError,
        'Faulty::Storage::FallbackChain#lock failed for some storage backends: fail'
      )

      expect(memory.status(circuit).locked_open?).to eq(true)
      expect(memory2.status(circuit).locked_open?).to eq(true)
    end

    it 'raises error if all storages fail' do
      expect do
        failing_chain.lock(circuit, :open)
      end.to raise_error(
        Faulty::AllFailedError,
        'Faulty::Storage::FallbackChain#lock failed for all storage backends: fail, fail'
      )
    end
  end

  shared_examples 'chained method' do
    it 'calls only first storage when successful' do
      chain = described_class.new([memory, instance_double(Faulty::Storage::Memory)], notifier: notifier)
      marker = Object.new
      expected = receive(action).and_return(marker)
      args.empty? ? expected.with(no_args) : expected.with(*args)
      expect(memory).to expected
      expect(chain.public_send(action, *args)).to eq(marker)
    end

    it 'falls back to next storage after failure' do
      event_payload = { action: action, error: be_a(RuntimeError) }
      event_payload[:circuit] = circuit unless action == :list
      expect(notifier).to receive(:notify).with(:storage_failure, event_payload)
      marker = Object.new
      expected = receive(action).and_return(marker)
      args.empty? ? expected.with(no_args) : expected.with(*args)
      expect(memory).to expected
      expect(partially_failing_chain.public_send(action, *args)).to eq(marker)
    end
  end

  shared_examples 'fan-out method' do
    it 'calls all backends' do
      chain = described_class.new([memory, memory2], notifier: notifier)
      expected = receive(action)
      args.empty? ? expected.with(no_args) : expected.with(*args)
      expect(memory).to expected
      expect(memory2).to expected
      expect(chain.public_send(action, *args)).to eq(nil)
    end
  end

  describe '#get_options' do
    let(:action) { :get_options }
    let(:args) { [circuit] }

    it_behaves_like 'chained method'
  end

  describe '#set_options' do
    let(:action) { :set_options }
    let(:args) { [circuit, { cool_down: 5 }] }

    it_behaves_like 'fan-out method'
  end

  describe '#open' do
    let(:action) { :open }
    let(:args) { [circuit, Faulty.current_time] }

    it_behaves_like 'chained method'
  end

  describe '#reopen' do
    let(:action) { :reopen }
    let(:args) { [circuit, Faulty.current_time, Faulty.current_time - 300] }

    it_behaves_like 'chained method'
  end

  describe '#close' do
    let(:action) { :close }
    let(:args) { [circuit] }

    it_behaves_like 'chained method'
  end

  describe '#lock' do
    let(:action) { :lock }
    let(:args) { [circuit, :open] }

    it_behaves_like 'fan-out method'
  end

  describe '#unlock' do
    let(:action) { :unlock }
    let(:args) { [circuit] }

    it_behaves_like 'fan-out method'
  end

  describe '#reset' do
    let(:action) { :reset }
    let(:args) { [circuit] }

    it_behaves_like 'fan-out method'
  end

  describe '#status' do
    let(:action) { :status }
    let(:args) { [circuit] }

    it_behaves_like 'chained method'
  end

  describe '#history' do
    let(:action) { :history }
    let(:args) { [circuit] }

    it_behaves_like 'chained method'
  end

  describe '#list' do
    let(:action) { :list }
    let(:args) { [] }

    it_behaves_like 'chained method'
  end

  it 'is fault tolerant if any storage is fault tolerant' do
    expect(described_class.new([Faulty::Storage::Redis.new, memory], notifier: notifier))
      .to be_fault_tolerant
  end

  it 'is not fault tolerant if no storage is fault tolerant' do
    expect(described_class.new(
      [Faulty::Storage::Redis.new, Faulty::Storage::Redis.new],
      notifier: notifier
    )).not_to be_fault_tolerant
  end
end
