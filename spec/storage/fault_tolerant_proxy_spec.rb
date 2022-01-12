# frozen_string_literal: true

RSpec.describe Faulty::Storage::FaultTolerantProxy do
  let(:notifier) { Faulty::Events::Notifier.new }

  let(:failing_storage_class) do
    Class.new do
      def method_missing(*_args) # rubocop:disable Style/MethodMissingSuper
        raise 'fail'
      end

      def respond_to_missing?(*_args)
        true
      end
    end
  end

  let(:failing_storage) { failing_storage_class.new }
  let(:inner_storage) { Faulty::Storage::Memory.new }
  let(:circuit) { Faulty::Circuit.new('test') }

  it 'delegates to storage when adding entry succeeds' do
    described_class.new(inner_storage, notifier: notifier)
      .entry(circuit, Faulty.current_time, true, nil)
    expect(inner_storage.history(circuit).size).to eq(1)
  end

  it 'returns stub status when adding entry fails' do
    expect(notifier).to receive(:notify)
      .with(:storage_failure, circuit: circuit, action: :entry, error: instance_of(RuntimeError))
    status = described_class.new(failing_storage, notifier: notifier)
      .entry(circuit, Faulty.current_time, false, Faulty::Status.new(options: circuit.options))
    expect(status.stub).to eq(true)
  end

  it 'returns stub status when getting #status' do
    expect(notifier).to receive(:notify)
      .with(:storage_failure, circuit: circuit, action: :status, error: instance_of(RuntimeError))
    status = described_class.new(failing_storage, notifier: notifier)
      .status(circuit)
    expect(status.stub).to eq(true)
  end

  shared_examples 'delegated action' do
    it 'delegates success to inner storage' do
      marker = Object.new
      expected = receive(action).and_return(marker)
      args.empty? ? expected.with(no_args) : expected.with(*args)
      expect(inner_storage).to expected
      result = described_class.new(inner_storage, notifier: notifier)
        .public_send(action, *args)
      expect(result).to eq(marker)
    end
  end

  shared_examples 'unsafe action' do
    it 'raises error on failure' do
      expect do
        described_class.new(failing_storage, notifier: notifier).public_send(action, *args)
      end.to raise_error('fail')
    end

    it_behaves_like 'delegated action'
  end

  shared_examples 'safely wrapped action' do
    it 'catches error and returns false' do
      expect(notifier).to receive(:notify)
        .with(:storage_failure, circuit: circuit, action: action, error: instance_of(RuntimeError))
      result = described_class.new(failing_storage, notifier: notifier)
        .public_send(action, *args)
      expect(result).to eq(retval)
    end

    it_behaves_like 'delegated action'
  end

  describe '#get_options' do
    let(:action) { :get_options }
    let(:args) { [circuit] }
    let(:retval) { nil }

    it_behaves_like 'safely wrapped action'
  end

  describe '#set_options' do
    let(:action) { :set_options }
    let(:args) { [circuit, { cool_down: 3 }] }
    let(:retval) { nil }

    it_behaves_like 'safely wrapped action'
  end

  describe '#open' do
    let(:action) { :open }
    let(:args) { [circuit, Faulty.current_time] }
    let(:retval) { false }

    it_behaves_like 'safely wrapped action'
  end

  describe '#reopen' do
    let(:action) { :reopen }
    let(:args) { [circuit, Faulty.current_time, Faulty.current_time - 300] }
    let(:retval) { false }

    it_behaves_like 'safely wrapped action'
  end

  describe '#close' do
    let(:action) { :close }
    let(:args) { [circuit] }
    let(:retval) { false }

    it_behaves_like 'safely wrapped action'
  end

  describe '#lock' do
    let(:action) { :lock }
    let(:args) { [circuit, :open] }

    it_behaves_like 'unsafe action'
  end

  describe '#unlock' do
    let(:action) { :unlock }
    let(:args) { [circuit] }

    it_behaves_like 'unsafe action'
  end

  describe '#reset' do
    let(:action) { :reset }
    let(:args) { [circuit] }

    it_behaves_like 'unsafe action'
  end

  describe '#history' do
    let(:action) { :history }
    let(:args) { [circuit] }

    it_behaves_like 'unsafe action'
  end

  describe '#list' do
    let(:action) { :list }
    let(:args) { [] }

    it_behaves_like 'unsafe action'
  end

  it 'raises when storage fails while getting list' do
    expect do
      described_class.new(failing_storage, notifier: notifier).list
    end.to raise_error('fail')
  end

  it 'is fault tolerant for non-fault-tolerant storage' do
    fault_tolerant = described_class.new(Faulty::Storage::Redis.new, notifier: notifier)
    expect(fault_tolerant).to be_fault_tolerant
  end

  describe '.wrap' do
    it 'returns fault-tolerant storage unmodified' do
      memory = Faulty::Storage::Memory.new
      expect(described_class.wrap(memory, notifier: notifier)).to eq(memory)
    end

    it 'wraps fault-tolerant cache' do
      redis = Faulty::Storage::Redis.new
      expect(described_class.wrap(redis, notifier: notifier)).to be_a(described_class)
    end
  end
end
