# frozen_string_literal: true

RSpec.describe Faulty::Scope do
  subject(:scope) { described_class.new(listeners: []) }

  it 'memoizes circuits' do
    expect(scope.circuit('test')).to eq(scope.circuit('test'))
  end

  it 'keeps options passed to the first instance and ignores others' do
    scope.circuit('test', cool_down: 404)
    expect(scope.circuit('test', cool_down: 302).options.cool_down).to eq(404)
  end

  it 'converts symbol names to strings' do
    expect(scope.circuit(:test)).to eq(scope.circuit('test'))
  end

  it 'lists circuit names' do
    scope.circuit('test1').run { 'ok' }
    scope.circuit('test2').run { 'ok' }
    expect(scope.list_circuits).to match_array(%w[test1 test2])
  end

  it 'does not wrap fault-tolerant storage' do
    storage = Faulty::Storage::Memory.new
    scope = described_class.new(storage: storage)
    expect(scope.options.storage).to equal(storage)
  end

  it 'does not wrap fault-tolerant cache' do
    cache = Faulty::Cache::Null.new
    scope = described_class.new(cache: cache)
    expect(scope.options.cache).to equal(cache)
  end

  it 'wraps non-fault-tolerant storage in FaultTolerantProxy' do
    scope = described_class.new(storage: Faulty::Storage::Redis.new)
    expect(scope.options.storage).to be_a(Faulty::Storage::FaultTolerantProxy)
  end

  it 'wraps non-fault-tolerant cache in FaultTolerantProxy' do
    scope = described_class.new(cache: Faulty::Cache::Rails.new(nil))
    expect(scope.options.cache).to be_a(Faulty::Cache::FaultTolerantProxy)
  end
end
