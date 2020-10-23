# frozen_string_literal: true

require 'connection_pool'
require 'redis'

RSpec.describe Faulty::Storage::Redis do
  subject(:storage) { described_class.new(**options.merge(client: client)) }

  let(:options) { {} }
  let(:client) { Redis.new(timeout: 1) }
  let(:circuit) { Faulty::Circuit.new('test', storage: storage) }

  after { circuit&.reset! }

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

  context 'when Redis has high timeout' do
    let(:client) { Redis.new(timeout: 5) }

    it 'prints timeout warning' do
      timeouts = { connect_timeout: 5.0, read_timeout: 5.0, write_timeout: 5.0 }
      expect { storage }.to output(/Your options are:\n#{timeouts}/).to_stderr
    end
  end

  context 'when Redis has high reconnect_attempts' do
    let(:client) { Redis.new(timeout: 1, reconnect_attempts: 3) }

    it 'prints reconnect_attempts warning' do
      expect { storage }.to output(/Your setting is 3/).to_stderr
    end
  end

  context 'when ConnectionPool has high timeout' do
    let(:client) do
      ConnectionPool.new(timeout: 6) { Redis.new(timeout: 1) }
    end

    it 'prints timeout warning' do
      expect { storage }.to output(/Your setting is 6/).to_stderr
    end
  end

  context 'when ConnectionPool Redis client has high timeout' do
    let(:client) do
      ConnectionPool.new(timeout: 1) { Redis.new(timeout: 7) }
    end

    it 'prints Redis timeout warning' do
      timeouts = { connect_timeout: 7.0, read_timeout: 7.0, write_timeout: 7.0 }
      expect { storage }.to output(/Your options are:\n#{timeouts}/).to_stderr
    end
  end

  context 'when an error is raised while checking settings' do
    let(:circuit) { nil }
    let(:client) do
      ConnectionPool.new(timeout: 1) { raise 'fail' }
    end

    it 'warns and continues' do
      expect { storage }.to output(/while checking client options: fail/).to_stderr
    end
  end
end
