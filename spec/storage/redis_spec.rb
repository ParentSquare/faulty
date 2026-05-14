# frozen_string_literal: true

require 'connection_pool'
require 'redis'

RSpec.describe Faulty::Storage::Redis do
  subject(:storage) { described_class.new(**options, client: client) }

  let(:options) { {} }
  let(:client) { Redis.new(timeout: 1) }
  let(:circuit) { Faulty::Circuit.new('test', storage: storage) }

  after { circuit&.reset! }

  context 'with default options' do
    subject(:storage) { described_class.new }

    it 'can add an entry' do
      storage.entry(circuit, Faulty.current_time, true, nil)
      expect(storage.history(circuit).size).to eq(1)
    end

    it 'clears circuits and list' do
      storage.entry(circuit, Faulty.current_time, true, nil)
      storage.clear
      expect(storage.list).to eq(%w[test])
      expect(storage.history(circuit)).to eq([])
    end
  end

  context 'with connection pool' do
    let(:pool_size) { 100 }

    let(:client) do
      ConnectionPool.new(size: pool_size, timeout: 1) { Redis.new(timeout: 1) }
    end

    it 'adds an entry' do
      storage.entry(circuit, Faulty.current_time, true, nil)
      expect(storage.history(circuit).size).to eq(1)
    end

    it 'opens the circuit once when called concurrently', :concurrency do
      concurrent_warmup do
        # Do something small just to get a connection from the pool
        storage.unlock(circuit)
      end

      result = concurrently(pool_size) do
        storage.open(circuit, Faulty.current_time)
      end
      expect(result.count { |r| r }).to eq(1)
    end

    it 'reserves the circuit once when called concurrently', :concurrency do
      concurrent_warmup do
        storage.unlock(circuit)
      end

      result = concurrently(pool_size) do
        storage.reserve(circuit, Faulty.current_time, nil)
      end
      expect(result.count { |r| r }).to eq(1)
    end
  end

  context 'when Redis has high timeout' do
    let(:client) { Redis.new(timeout: 5.0) }

    it 'prints timeout warning' do
      timeouts = { connect_timeout: 5.0, read_timeout: 5.0, write_timeout: 5.0 }
      expect { storage }.to output(/Your options are:\n#{timeouts}/).to_stderr
    end
  end

  context 'when Redis has high reconnect_attempts' do
    let(:client) { Redis.new(timeout: 1, reconnect_attempts: 2) }

    it 'prints reconnect_attempts warning' do
      expect { storage }.to output(/Your setting is larger/).to_stderr
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
      ConnectionPool.new(timeout: 1) { Redis.new(timeout: 7.0) }
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

  # See spec/storage/memory_spec.rb for the rationale: preserving reserved_at
  # across reopen is load-bearing for half-open exclusivity against
  # late-arriving callers whose status snapshot saw reserved_at == nil from
  # before the winning process reserved.
  it 'does not clear reserved_at on reopen' do
    storage.open(circuit, 100.0)
    storage.reserve(circuit, 100.0, nil)
    storage.reopen(circuit, 200.0, 100.0)
    expect(storage.status(circuit).reserved_at).to eq(100.0)
  end

  context 'when opened_at is missing and status is open' do
    it 'sets opened_at to the maximum' do
      Timecop.freeze
      storage.open(circuit, Faulty.current_time)
      client.del('faulty:circuit:test:opened_at')
      status = storage.status(circuit)
      expect(status.opened_at).to eq(Faulty.current_time - storage.options.circuit_ttl)
    end
  end

  context 'when history entries are integers and floats' do
    it 'gets floats' do
      client.lpush('faulty:circuit:test:entries', '1660865630:1')
      client.lpush('faulty:circuit:test:entries', '1660865646.897674:1')
      expect(storage.history(circuit)).to eq([[1_660_865_630.0, true], [1_660_865_646.897674, true]])
    end
  end

  context 'when ConnectionPool is not present' do
    before { hide_const('ConnectionPool') }

    it 'can construct a storage' do
      expect { storage }.not_to raise_error
    end
  end
end
