# frozen_string_literal: true

RSpec.describe Faulty::Storage::AutoWire do
  subject(:auto_wire) { described_class.wrap(backend, circuit: circuit, notifier: notifier) }

  let(:circuit) { Faulty::Circuit.new('test') }
  let(:notifier) { Faulty::Events::Notifier.new }
  let(:backend) { nil }

  context 'with a fault-tolerant backend' do
    let(:backend) { Faulty::Storage::Memory.new }

    it 'delegates directly if a fault-tolerant backend is given' do
      expect(auto_wire).to eq(backend)
    end
  end

  context 'with a non-fault-tolerant backend' do
    let(:backend) { Faulty::Storage::Redis.new }

    it 'is fault tolerant' do
      expect(auto_wire).to be_fault_tolerant
    end

    it 'wraps in FaultTolerantProxy and CircuitProxy' do
      expect(auto_wire).to be_a(Faulty::Storage::FaultTolerantProxy)

      circuit_proxy = auto_wire.instance_variable_get(:@storage)
      expect(circuit_proxy).to be_a(Faulty::Storage::CircuitProxy)
      expect(circuit_proxy.options.circuit).to eq(circuit)

      original = circuit_proxy.instance_variable_get(:@storage)
      expect(original).to eq(backend)
    end
  end

  context 'with a fault-tolerant array' do
    let(:redis_storage) { Faulty::Storage::Redis.new }
    let(:mem_storage) { Faulty::Storage::Memory.new }
    let(:backend) { [redis_storage, mem_storage] }

    it 'creates a FallbackChain' do
      expect(auto_wire).to be_a(Faulty::Storage::FallbackChain)

      storages = auto_wire.instance_variable_get(:@storages)
      expect(storages[0]).to be_a(Faulty::Storage::CircuitProxy)
      expect(storages[0].instance_variable_get(:@storage)).to eq(redis_storage)
      expect(storages[1]).to eq(mem_storage)
    end
  end

  context 'with a non-fault-tolerant array' do
    let(:redis_storage1) { Faulty::Storage::Redis.new }
    let(:redis_storage2) { Faulty::Storage::Redis.new }
    let(:backend) { [redis_storage1, redis_storage2] }

    it 'creates a FallbackChain inside a FaultTolerantProxy' do
      expect(auto_wire).to be_a(Faulty::Storage::FaultTolerantProxy)

      chain = auto_wire.instance_variable_get(:@storage)
      expect(chain).to be_a(Faulty::Storage::FallbackChain)

      storages = chain.instance_variable_get(:@storages)
      expect(storages[0]).to be_a(Faulty::Storage::CircuitProxy)
      expect(storages[0].instance_variable_get(:@storage)).to eq(redis_storage1)
      expect(storages[1]).to be_a(Faulty::Storage::CircuitProxy)
      expect(storages[1].instance_variable_get(:@storage)).to eq(redis_storage2)
    end
  end
end
