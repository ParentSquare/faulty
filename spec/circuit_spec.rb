# frozen_string_literal: true

require 'redis'

RSpec.context :circuits do
  let(:circuit) { Faulty::Circuit.new('test', **options) }

  let(:open_circuit) do
    circuit = Faulty::Circuit.new('test', **options.merge(rate_threshold: 0, sample_threshold: 0))
    circuit.try_run { raise 'failed' }
    circuit
  end

  let(:options) do
    {
      cache: cache,
      storage: storage
    }
  end

  let(:cache) { Faulty::Cache::Mock.new }

  let(:custom_error_base) do
    stub_const('TestErrorBase', Class.new(RuntimeError))
  end

  let(:custom_error_module) do
    stub_const('TestErrors', Module.new)
    Faulty::Patch.define_circuit_errors(TestErrors, custom_error_base)
    TestErrors
  end

  it 'can be constructed with only a name' do
    circuit = Faulty::Circuit.new('plain')
    expect(circuit.name).to eq('plain')
  end

  shared_examples 'circuit' do
    it 'runs a circuit with no errors' do
      expect(circuit.run { 'ok' }).to eq('ok')
    end

    it 'gets an ok result with try_run' do
      result = circuit.try_run { 'ok' }
      expect(result.ok?).to eq(true)
      expect(result.get).to eq('ok')
    end

    it 'captures an error with try_run' do
      result = circuit.try_run { raise 'fail' }
      expect(result.error?).to eq(true)
      expect(result.error.cause.message).to eq('fail')
    end

    it 'raises a CircuitFailureError when an error is raised' do
      expect do
        circuit.run { raise 'failed' }
      end.to raise_error(
        an_instance_of(Faulty::CircuitFailureError)
        .and(having_attributes(message: 'circuit error for "test"', circuit: circuit))
      )
    end

    it 'raises a CircuitTrippedError when the threshold is passed' do
      circuit = Faulty::Circuit.new('test', **options.merge(rate_threshold: 0, sample_threshold: 0))
      expect do
        circuit.run { raise 'failed' }
      end.to raise_error(
        an_instance_of(Faulty::CircuitTrippedError)
        .and(having_attributes(message: 'circuit error for "test"', circuit: circuit))
      )
    end

    it 'raises an OpenCircuitError when the circuit is open' do
      expect do
        open_circuit.run { 'ok' }
      end.to raise_error(
        an_instance_of(Faulty::OpenCircuitError)
        .and(having_attributes(message: 'circuit error for "test"', circuit: open_circuit))
      )
    end

    it 'raises an OpenCircuitError when locked open' do
      circuit.lock_open!
      expect { circuit.run { 'ok' } }.to raise_error(Faulty::OpenCircuitError)
    end

    it 'ignores open state when locked closed' do
      open_circuit.lock_closed!
      expect(open_circuit.run { 'ok' }).to eq('ok')
    end

    it 'can be unlocked from the locked_open state' do
      circuit.lock_open!
      circuit.unlock!
      expect(circuit.run { 'ok' }).to eq('ok')
    end

    it 'can be unlocked from the locked_closed state' do
      open_circuit.lock_closed!
      open_circuit.unlock!
      expect { open_circuit.run { 'ok' } }.to raise_error(Faulty::OpenCircuitError)
    end

    it 'gets recent history' do
      Timecop.freeze
      circuit.run { 'ok' }
      circuit.try_run { raise 'failed' }
      expect(circuit.history).to eq([[Time.now.to_i, true], [Time.now.to_i, false]])
    end

    it 'clears stats and history when reset' do
      circuit.run { 'ok' }
      circuit.try_run { raise 'failed' }
      circuit.lock_open!
      circuit.reset!
      expect(circuit.history).to eq([])
      expect(circuit.status.closed?).to eq(true)
      expect(circuit.status.locked_open?).to eq(false)
    end

    it 'does not close circuit until past sample threshold' do
      circuit = Faulty::Circuit.new('test', **options.merge(rate_threshold: 0, sample_threshold: 2))
      circuit.try_run { raise 'fail' }
      expect(circuit.status.closed?).to eq(true)
      circuit.try_run { raise 'fail' }
      expect(circuit.status.open?).to eq(true)
    end

    it 'does not close circuit until past rate threshold' do
      circuit = Faulty::Circuit.new('test', **options.merge(rate_threshold: 0.6, sample_threshold: 0))
      circuit.try_run { 'ok' }
      circuit.try_run { raise 'fail' }
      expect(circuit.status.closed?).to eq(true)
      circuit.try_run { raise 'fail' }
      expect(circuit.status.open?).to eq(true)
    end

    it 'transitions from open to half-open after cool-down elapses' do
      open_circuit
      Timecop.freeze(Time.now + 300)
      expect(open_circuit.status.half_open?).to eq(true)
    end

    it 'opens circuit if it fails in half-open' do
      open_circuit
      Timecop.freeze(Time.now + 300)
      result = open_circuit.try_run { raise 'fail' }
      expect(result.error?).to eq(true)
      expect(open_circuit.status.open?).to eq(true)
    end

    it 'closes circuit if it succeeds in half-open' do
      open_circuit
      Timecop.freeze(Time.now + 300)
      result = open_circuit.run { 'ok' }
      expect(result).to eq('ok')
      expect(open_circuit.status.closed?).to eq(true)
    end

    it 'skips running if open' do
      ran = false
      open_circuit.try_run { ran = true }
      expect(ran).to eq(false)
    end

    it 'reads from the cache if available and does not run' do
      cache.write('test_cache', 'cached')
      result = circuit.run(cache: 'test_cache') { raise 'This should not run' }
      expect(result).to eq('cached')
    end

    it 'writes to the cache if successful' do
      circuit.run(cache: 'test_cache') { 'cached' }
      expect(cache.read('test_cache')).to eq('cached')
    end

    it 'refreshes the cache when available but after refresh_after' do
      circuit.run(cache: 'test_cache') { 'cached' }
      Timecop.freeze(Time.now + 5000)
      result = circuit.run(cache: 'test_cache') { 'new_cache' }
      expect(result).to eq('new_cache')
      expect(cache.read('test_cache')).to eq('new_cache')
    end

    it 'reads from the cache if open and within expiration' do
      circuit.run(cache: 'test_cache') { 'cached' }
      circuit.lock_open!
      Timecop.freeze(Time.now + 5000)
      result = circuit.run(cache: 'test_cache') { raise 'This should not run' }
      expect(result).to eq('cached')
    end

    it 'falls back to cache if failed and within expiration' do
      circuit.run(cache: 'test_cache') { 'cached' }
      Timecop.freeze(Time.now + 5000)
      result = circuit.run(cache: 'test_cache') { raise 'fail' }
      expect(result).to eq('cached')
    end

    it 'raises unwrapped error if error is excluded' do
      test_error = Class.new(StandardError)
      circuit = Faulty::Circuit.new('test', **options.merge(exclude: test_error))
      expect do
        circuit.run { raise test_error }
      end.to raise_error(test_error)
    end

    it 'raises unwrapped error if error is not included' do
      test_error = Class.new(StandardError)
      circuit = Faulty::Circuit.new('test', **options.merge(errors: test_error))
      expect do
        circuit.run { raise StandardError, 'test' }
      end.to raise_error(StandardError, 'test')
    end

    it 'raises all unwrapped errors if errors option is empty' do
      circuit = Faulty::Circuit.new('test', **options.merge(errors: []))
      expect do
        circuit.run { raise 'fail' }
      end.to raise_error(RuntimeError, 'fail')
    end

    it 'applies jitter to cache refresh' do
      allow(circuit).to receive(:rand).and_return(1)

      circuit.run(cache: 'cache_test') { 'ok' }
      Timecop.freeze(Time.now + 1000)
      result = circuit.run(cache: 'cache_test') { 'foo' }
      expect(result).to eq('ok')
      Timecop.freeze(Time.now + 200)
      result = circuit.run(cache: 'cache_test') { 'new' }
      expect(result).to eq('new')
    end

    context 'with error_module' do
      let(:options) do
        {
          cache: cache,
          error_module: custom_error_module,
          storage: storage
        }
      end

      it 'raises custom errors' do
        expect do
          circuit.run { raise 'fail' }
        end.to raise_error(custom_error_module::CircuitFailureError)
      end
    end
  end

  context 'with memory storage' do
    let(:storage) { Faulty::Storage::Memory.new }

    it_behaves_like 'circuit'
  end

  context 'with redis storage' do
    let(:storage) { Faulty::Storage::Redis.new }

    after { circuit.reset! }

    it_behaves_like 'circuit'
  end

  context 'with fault-tolerant redis storage' do
    let(:storage) do
      Faulty::Storage::FaultTolerantProxy.new(
        Faulty::Storage::Redis.new,
        notifier: Faulty::Events::Notifier.new
      )
    end

    after { circuit.reset! }

    it_behaves_like 'circuit'
  end
end
