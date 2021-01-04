# frozen_string_literal: true

RSpec.describe Faulty::Storage::ExpiringMemoryStore do
  subject(:store) { described_class.new(**options) }

  let(:options) { { granularity: 5, ttl: 15 } }

  it 'sets a value when not present' do
    expect(store.compute_if_absent(:foo) { 'my value' }).to eq('my value')
    expect(store.compute_if_absent(:foo) { 'not used' }).to eq('my value')
  end

  it 'maintains value if used continuously' do
    Timecop.freeze
    store.compute_if_absent(:foo) { 'my value' }
    Timecop.freeze(Time.now + 5)
    expect(store.compute_if_absent(:foo) { 'not used' }).to eq('my value')
    Timecop.freeze(Time.now + 5)
    expect(store.compute_if_absent(:foo) { 'not used' }).to eq('my value')
    Timecop.travel(Time.now + 5)
    expect(store.compute_if_absent(:foo) { 'not used' }).to eq('my value')
  end

  it 'expires value if unused after ttl' do
    Timecop.freeze
    expect(store.compute_if_absent(:foo) { 'my value' }).to eq('my value')
    Timecop.freeze(Time.now + 15)
    expect(store.compute_if_absent(:foo) { 'new value' }).to eq('new value')
  end

  it 'drops reference to value after ttl' do
    Timecop.freeze

    # Create an object, store it, then drop our reference to it
    value = Object.new
    id = value.object_id
    store.compute_if_absent(:foo) { value }
    value = nil

    # Do a full rotation of buckets
    Timecop.freeze(Time.now + 15)

    # Need to trigger reference drop by doing another operation on the store
    # to reset the bucket to an empty one
    store.compute_if_absent(:not_used) { nil }
    GC.start

    # Our value has been GC'd
    expect { ObjectSpace._id2ref(id) }.to raise_error(RangeError)
    expect(store.compute_if_absent(:foo) { 'new value' }).to eq('new value')
  end

  it 'gets keys only if not expired' do
    Timecop.freeze
    store.compute_if_absent(:a) { nil }
    Timecop.freeze(Time.now + 5)
    store.compute_if_absent(:b) { nil }
    store.compute_if_absent(:c) { nil }

    expect(store.keys).to eq(%i[a b c])
    Timecop.freeze(Time.now + 10)
    expect(store.keys).to eq(%i[b c])
  end

  it 'removes value when key is deleted' do
    store.compute_if_absent(:foo) { 'my value' }
    store.delete(:foo)
    expect(store.compute_if_absent(:foo) { 'new value' }).to eq('new value')
  end

  it 'drops value reference when key is deleted' do
    Timecop.freeze
    value = Object.new
    id = value.object_id
    store.compute_if_absent(:foo) { value }
    value = nil

    store.compute_if_absent(:foo) { 'my value' }
    store.delete(:foo)
    GC.start
    expect { ObjectSpace._id2ref(id) }.to raise_error(RangeError)
  end
end
