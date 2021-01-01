# frozen_string_literal: true

RSpec.describe Faulty::Patch do
  let(:error_base) do
    stub_const('TestErrorBase', Class.new(RuntimeError))
  end

  describe '.circuit_from_hash' do
    let(:faulty) { Faulty.new }

    let(:error_module) do
      stub_const('TestErrors', Module.new)
      described_class.define_circuit_errors(TestErrors, error_base)
      TestErrors
    end

    after do
      described_class.instance_variable_set(:@instances, nil)
      described_class.instance_variable_set(:@default_instance, nil)
    end

    it 'can specify an instance' do
      circuit = described_class.circuit_from_hash('test', { instance: faulty })
      expect(faulty.circuit('test')).to eq(circuit)
    end

    it 'returns nil if hash is nil' do
      circuit = described_class.circuit_from_hash('test', nil)
      expect(circuit).to eq(nil)
    end

    it 'can specify a custom name' do
      circuit = described_class.circuit_from_hash('test', { instance: faulty, name: 'my_test' })
      expect(faulty.circuit('my_test')).to eq(circuit)
    end

    it 'passes circuit options to the circuit' do
      circuit = described_class.circuit_from_hash('test', { instance: faulty, sample_threshold: 10 })
      expect(circuit.options.sample_threshold).to eq(10)
    end

    it 'overrides hash options with keyword arg' do
      circuit = described_class.circuit_from_hash(
        'test',
        {
          instance: faulty,
          sample_threshold: 10
        },
        sample_threshold: 20
      )
      expect(circuit.options.sample_threshold).to eq(20)
    end

    it 'overrides hash options with block' do
      circuit = described_class.circuit_from_hash('test', { instance: faulty, sample_threshold: 10 }) do |config|
        config.sample_threshold = 30
      end
      expect(circuit.options.sample_threshold).to eq(30)
    end

    context 'when patch_errors is enabled' do
      it 'sets error_module' do
        circuit = described_class.circuit_from_hash(
          'test',
          { instance: faulty },
          patched_error_module: error_module
        )
        expect(circuit.options.error_module).to eq(error_module)
      end
    end

    context 'when patch_errors is enabled but patched_error_module is missing' do
      it 'uses Faulty error module' do
        circuit = described_class.circuit_from_hash(
          'test',
          { instance: faulty, patch_errors: true }
        )
        expect(circuit.options.error_module).to eq(Faulty)
      end
    end

    context 'when user sets error_module manually' do
      it 'overrides patched_error_module' do
        circuit = described_class.circuit_from_hash(
          'test',
          { instance: faulty, error_module: Faulty }
        )
        expect(circuit.options.error_module).to eq(Faulty)
      end
    end

    context 'when patch_errors is disabled' do
      it 'uses Faulty error module' do
        circuit = described_class.circuit_from_hash(
          'test',
          { instance: faulty, patch_errors: false }
        )
        expect(circuit.options.error_module).to eq(Faulty)
      end
    end

    context 'with Faulty.default' do
      before { Faulty.init }

      it 'can be run with empty hash' do
        circuit = described_class.circuit_from_hash('test', {})
        expect(Faulty.circuit('test')).to eq(circuit)
      end
    end

    context 'with constant name' do
      before { stub_const('MY_FAULTY', faulty) }

      it 'gets instance by constant name' do
        circuit = described_class.circuit_from_hash('test', { instance: { constant: :MY_FAULTY } })
        expect(faulty.circuit('test')).to eq(circuit)
      end

      it 'can pass in string keys and constant name' do
        circuit = described_class.circuit_from_hash('test', { 'instance' => { 'constant' => 'MY_FAULTY' } })
        expect(faulty.circuit('test')).to eq(circuit)
      end
    end

    context 'with symbol name' do
      it 'gets registered instance by symbol' do
        Faulty.register(:my_faulty, faulty)
        circuit = described_class.circuit_from_hash('test', { instance: :my_faulty })
        expect(faulty.circuit('test')).to eq(circuit)
      end
    end
  end

  describe '.define_circuit_errors' do
    let(:namespace) do
      stub_const('TestErrors', Module.new)
    end

    it 'creates all circuit error classes in the namespace' do
      described_class.define_circuit_errors(namespace, error_base)
      expect(TestErrors::CircuitError.superclass).to eq(TestErrorBase)
      expect(TestErrors::CircuitError.ancestors).to include(Faulty::CircuitErrorBase)
      expect(TestErrors::OpenCircuitError.superclass).to eq(TestErrors::CircuitError)
      expect(TestErrors::CircuitFailureError.superclass).to eq(TestErrors::CircuitError)
      expect(TestErrors::CircuitTrippedError.superclass).to eq(TestErrors::CircuitError)
    end
  end
end
