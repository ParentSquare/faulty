# frozen_string_literal: true

RSpec.describe Faulty::Cache::AutoWire do
  subject(:auto_wire) { described_class.new(backend, notifier: notifier) }

  let(:notifier) { Faulty::Events::Notifier.new }
  let(:backend) { nil }

  # Typically it's a bad idea to test private interfaces, but in this case
  # we're specifically interested in testing the implementation. The alternative
  # would be to re-test functionality of each internal cache, and that seems
  # like a worse alternative.
  let(:internal) { auto_wire.instance_variable_get(:@cache) }

  context 'with nil backend' do
    it 'creates a new Default' do
      expect(internal).to be_a(Faulty::Cache::Default)
    end

    shared_examples 'delegator to internal' do
      it do
        marker = Object.new
        expect(internal).to receive(action).with(*args).and_return(marker)
        expect(auto_wire.public_send(action, *args)).to eq(marker)
      end
    end

    describe '#read' do
      let(:action) { :read }
      let(:args) { ['foo'] }

      it_behaves_like 'delegator to internal'
    end

    describe '#write' do
      let(:action) { :write }
      let(:args) { %w[foo val] }

      it_behaves_like 'delegator to internal'
    end
  end

  context 'with a fault-tolerant backend' do
    let(:backend) { Faulty::Cache::Mock.new }

    it 'delegates directly if a fault-tolerant backend is given' do
      expect(internal).to eq(backend)
    end
  end

  context 'with a non-fault-tolerant backend' do
    let(:backend) { Faulty::Cache::Rails.new(nil, fault_tolerant: false) }

    it 'is fault tolerant' do
      expect(auto_wire).to be_fault_tolerant
    end

    it 'wraps in FaultTolerantProxy and CircuitProxy' do
      expect(internal).to be_a(Faulty::Cache::FaultTolerantProxy)

      circuit_proxy = internal.instance_variable_get(:@cache)
      expect(circuit_proxy).to be_a(Faulty::Cache::CircuitProxy)

      original = circuit_proxy.instance_variable_get(:@cache)
      expect(original).to eq(backend)
    end
  end
end
