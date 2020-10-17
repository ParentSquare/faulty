# frozen_string_literal: true

require 'connection_pool'

RSpec.describe Faulty::Storage::Redis do
  subject(:storage) { described_class.new(**options.merge(client: client)) }

  let(:options) { {} }
  let(:client) { Redis.new }
  let(:circuit) { Faulty::Circuit.new('test', storage: storage) }

  after { circuit.reset! }

  context 'with default options' do
    subject(:storage) { described_class.new }

    it 'can add an entry' do
      storage.entry(circuit, Faulty.current_time, true)
      expect(storage.history(circuit).size).to eq(1)
    end
  end

  context 'with connection pool' do
    let(:pool_size) { 100 }

    let(:client) do
      ConnectionPool.new(size: pool_size, timeout: 1) { Redis.new(timeout: 1) }
    end

    it 'adds an entry' do
      storage.entry(circuit, Faulty.current_time, true)
      expect(storage.history(circuit).size).to eq(1)
    end

    it 'opens the circuit once when called concurrently', concurrency: true do
      concurrent_warmup do
        # Do something small just to get a connection from the pool
        storage.unlock(circuit)
      end

      result = concurrently(pool_size) do
        storage.open(circuit, Faulty.current_time)
      end
      expect(result.count { |r| r }).to eq(1)
    end
  end
end
