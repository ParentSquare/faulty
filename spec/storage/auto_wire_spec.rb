# frozen_string_literal: true

RSpec.describe Faulty::Storage::AutoWire do
  subject(:auto_wire) { described_class.new(backend, notifier: notifier) }

  let(:notifier) { Faulty::Events::Notifier.new }
  let(:backend) { nil }

  # Typically it's a bad idea to test private interfaces, but in this case
  # we're specifically interested in testing the implementation. The alternative
  # would be to re-test functionality of each internal storage, and that seems
  # like a worse alternative.
  let(:internal) { auto_wire.instance_variable_get(:@storage) }

  context 'with nil backend' do
    it 'creates a new Memory' do
      expect(internal).to be_a(Faulty::Storage::Memory)
    end

    shared_examples 'delegator to internal' do
      let(:circuit) { Faulty::Circuit.new('test', notifier: notifier) }
      it do
        marker = Object.new
        expected = receive(action).and_return(marker)
        args.empty? ? expected.with(no_args) : expected.with(*args)
        expect(internal).to expected
        expect(auto_wire.public_send(action, *args)).to eq(marker)
      end
    end

    describe '#open' do
      let(:action) { :open }
      let(:args) { [circuit, Faulty.current_time] }

      it_behaves_like 'delegator to internal'
    end

    describe '#reopen' do
      let(:action) { :reopen }
      let(:args) { [circuit, Faulty.current_time, Faulty.current_time - 300] }

      it_behaves_like 'delegator to internal'
    end

    describe '#close' do
      let(:action) { :close }
      let(:args) { [circuit] }

      it_behaves_like 'delegator to internal'
    end

    describe '#lock' do
      let(:action) { :lock }
      let(:args) { [circuit, :open] }

      it_behaves_like 'delegator to internal'
    end

    describe '#unlock' do
      let(:action) { :unlock }
      let(:args) { [circuit] }

      it_behaves_like 'delegator to internal'
    end

    describe '#reset' do
      let(:action) { :reset }
      let(:args) { [circuit] }

      it_behaves_like 'delegator to internal'
    end

    describe '#status' do
      let(:action) { :status }
      let(:args) { [circuit] }

      it_behaves_like 'delegator to internal'
    end

    describe '#history' do
      let(:action) { :history }
      let(:args) { [circuit] }

      it_behaves_like 'delegator to internal'
    end

    describe '#list' do
      let(:action) { :list }
      let(:args) { [] }

      it_behaves_like 'delegator to internal'
    end
  end

  context 'with a fault-tolerant backend' do
    let(:backend) { Faulty::Storage::Memory.new }

    it 'delegates directly if a fault-tolerant backend is given' do
      expect(internal).to eq(backend)
    end
  end

  context 'with a non-fault-tolerant backend' do
    let(:backend) { Faulty::Storage::Redis.new }

    it 'is fault tolerant' do
      expect(auto_wire).to be_fault_tolerant
    end

    it 'wraps in FaultTolerantProxy and CircuitProxy' do
      expect(internal).to be_a(Faulty::Storage::FaultTolerantProxy)

      circuit_proxy = internal.instance_variable_get(:@storage)
      expect(circuit_proxy).to be_a(Faulty::Storage::CircuitProxy)

      original = circuit_proxy.instance_variable_get(:@storage)
      expect(original).to eq(backend)
    end
  end

  context 'with a fault-tolerant array' do
    let(:redis_storage) { Faulty::Storage::Redis.new }
    let(:mem_storage) { Faulty::Storage::Memory.new }
    let(:backend) { [redis_storage, mem_storage] }

    it 'creates a FallbackChain' do
      expect(internal).to be_a(Faulty::Storage::FallbackChain)

      storages = internal.instance_variable_get(:@storages)
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
      expect(internal).to be_a(Faulty::Storage::FaultTolerantProxy)

      chain = internal.instance_variable_get(:@storage)
      expect(chain).to be_a(Faulty::Storage::FallbackChain)

      storages = chain.instance_variable_get(:@storages)
      expect(storages[0]).to be_a(Faulty::Storage::CircuitProxy)
      expect(storages[0].instance_variable_get(:@storage)).to eq(redis_storage1)
      expect(storages[1]).to be_a(Faulty::Storage::CircuitProxy)
      expect(storages[1].instance_variable_get(:@storage)).to eq(redis_storage2)
    end
  end
end
