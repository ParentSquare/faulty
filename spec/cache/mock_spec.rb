# frozen_string_literal: true

RSpec.describe Faulty::Cache::Mock do
  subject(:cache) { described_class.new }

  it 'writes and reads a value' do
    cache.write('a key', 'a value')
    expect(cache.read('a key')).to eq('a value')
  end

  it 'expires values after expires_in' do
    cache.write('a key', 'a value', expires_in: 10)
    Timecop.travel(Time.now + 5)
    expect(cache.read('a key')).to eq('a value')
    Timecop.travel(Time.now + 6)
    expect(cache.read('a key')).to eq(nil)
  end

  it 'is fault tolerant' do
    expect(cache).to be_fault_tolerant
  end
end
