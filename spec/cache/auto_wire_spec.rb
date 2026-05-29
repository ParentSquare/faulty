# frozen_string_literal: true

RSpec.describe Faulty::Cache::AutoWire do
  subject(:auto_wire) { described_class.wrap(backend, circuit: circuit, notifier: notifier) }

  let(:circuit) { Faulty::Circuit.new('test') }
  let(:notifier) { Faulty::Events::Notifier.new }
  let(:backend) { nil }

  context 'with a fault-tolerant backend' do
    let(:backend) { Faulty::Cache::Mock.new }

    it 'delegates directly if a fault-tolerant backend is given' do
      expect(auto_wire).to eq(backend)
    end
  end

  context 'with a nil backend' do
    let(:backend) { nil }

    it 'is fault tolerant' do
      expect(auto_wire).to be_fault_tolerant
    end

    context 'when Default resolves to a non-fault-tolerant backend' do
      before do
        allow(Faulty::Cache::Default).to receive(:new).and_return(
          Faulty::Cache::Rails.new(nil, fault_tolerant: false)
        )
      end

      it 'wraps Default in FaultTolerantProxy and CircuitProxy' do
        expect(auto_wire).to be_a(Faulty::Cache::FaultTolerantProxy)

        circuit_proxy = auto_wire.instance_variable_get(:@cache)
        expect(circuit_proxy).to be_a(Faulty::Cache::CircuitProxy)
        expect(circuit_proxy.options.circuit).to eq(circuit)
      end
    end

    context 'when Default resolves to a fault-tolerant backend' do
      let(:default) { Faulty::Cache::Null.new }

      before { allow(Faulty::Cache::Default).to receive(:new).and_return(default) }

      it 'returns Default unwrapped' do
        expect(auto_wire).to eq(default)
      end
    end
  end

  context 'with a non-fault-tolerant backend' do
    let(:backend) { Faulty::Cache::Rails.new(nil, fault_tolerant: false) }

    it 'is fault tolerant' do
      expect(auto_wire).to be_fault_tolerant
    end

    it 'wraps in FaultTolerantProxy and CircuitProxy' do
      expect(auto_wire).to be_a(Faulty::Cache::FaultTolerantProxy)

      circuit_proxy = auto_wire.instance_variable_get(:@cache)
      expect(circuit_proxy).to be_a(Faulty::Cache::CircuitProxy)
      expect(circuit_proxy.options.circuit).to eq(circuit)

      original = circuit_proxy.instance_variable_get(:@cache)
      expect(original).to eq(backend)
    end
  end
end
