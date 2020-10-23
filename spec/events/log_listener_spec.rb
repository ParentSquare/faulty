# frozen_string_literal: true

RSpec.describe Faulty::Events::LogListener do
  subject(:listener) { described_class.new(logger) }

  let(:logger) do
    logger = ::Logger.new(io)
    logger.level = :debug
    logger
  end
  let(:io) { StringIO.new }
  let(:circuit) { Faulty::Circuit.new('test', notifier: notifier, cache: cache) }
  let(:error) { StandardError.new('fail') }
  let(:notifier) { Faulty::Events::Notifier.new }
  let(:cache) { Faulty::Cache::Null.new }
  let(:status) { Faulty::Status.new({ options: circuit.options }) }
  let(:logs) do
    io.rewind
    io.read.strip
  end

  context 'when Rails is available' do
    before do
      l = logger
      stub_const(
        'Rails',
        Class.new do
          define_singleton_method(:logger) do
            l
          end
        end
      )
    end

    it 'logs to Rails logger by default' do
      described_class.new.handle(:circuit_success, circuit: circuit, status: status)
      expect(logs).to end_with('DEBUG -- : Circuit succeeded: test state=closed')
    end
  end

  it 'logs to stderr by default if Rails is not present' do
    expect do
      described_class.new.handle(:circuit_success, circuit: circuit, status: status)
    end.to output(/DEBUG -- : Circuit succeeded: test state=closed$/).to_stderr
  end

  # cache_failure
  # circuit_cache_hit
  # circuit_cache_miss
  # circuit_cache_write
  # circuit_closed
  # circuit_failure
  # circuit_opened
  # circuit_reopened
  # circuit_skipped
  # circuit_success
  # storage_failure

  it 'logs cache_failure' do
    listener.handle(:cache_failure, key: 'foo', action: :read, error: error)
    expect(logs).to end_with('ERROR -- : Cache failure: read key=foo error=fail')
  end

  it 'logs circuit_cache_hit' do
    listener.handle(:circuit_cache_hit, circuit: circuit, key: 'foo')
    expect(logs).to end_with('DEBUG -- : Circuit cache hit: test key=foo')
  end

  it 'logs circuit_cache_miss' do
    listener.handle(:circuit_cache_miss, circuit: circuit, key: 'foo')
    expect(logs).to end_with('DEBUG -- : Circuit cache miss: test key=foo')
  end

  it 'logs circuit_cache_write' do
    listener.handle(:circuit_cache_write, circuit: circuit, key: 'foo')
    expect(logs).to end_with('DEBUG -- : Circuit cache write: test key=foo')
  end

  it 'logs circuit_closed' do
    listener.handle(:circuit_closed, circuit: circuit)
    expect(logs).to end_with('INFO -- : Circuit closed: test')
  end

  it 'logs circuit_failure' do
    listener.handle(:circuit_failure, circuit: circuit, status: status, error: error)
    expect(logs).to end_with('ERROR -- : Circuit failed: test state=closed error=fail')
  end

  it 'logs circuit_opened' do
    listener.handle(:circuit_opened, circuit: circuit, error: error)
    expect(logs).to end_with('ERROR -- : Circuit opened: test error=fail')
  end

  it 'logs circuit_reopened' do
    listener.handle(:circuit_reopened, circuit: circuit, error: error)
    expect(logs).to end_with('ERROR -- : Circuit reopened: test error=fail')
  end

  it 'logs circuit_skipped' do
    listener.handle(:circuit_skipped, circuit: circuit)
    expect(logs).to end_with('WARN -- : Circuit skipped: test')
  end

  it 'logs circuit_success' do
    listener.handle(:circuit_success, circuit: circuit, status: status)
    expect(logs).to end_with('DEBUG -- : Circuit succeeded: test state=closed')
  end

  it 'logs storage_failure with circuit' do
    listener.handle(:storage_failure, circuit: circuit, action: :entry, error: error)
    expect(logs).to end_with('ERROR -- : Storage failure: entry circuit=test error=fail')
  end

  it 'logs storage_failure without circuit' do
    listener.handle(:storage_failure, action: :list, error: error)
    expect(logs).to end_with('ERROR -- : Storage failure: list error=fail')
  end
end
