# frozen_string_literal: true

RSpec.describe Faulty::Cache::Null do
  subject(:cache) { described_class.new }

  it 'reads nothing after writing' do
    cache.write('foo', 'bar')
    expect(cache.read('foo')).to be_nil
  end

  it 'is fault_tolerant' do
    expect(cache.fault_tolerant?).to be(true)
  end
end
