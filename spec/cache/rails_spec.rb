# frozen_string_literal: true

RSpec.describe Faulty::Cache::Rails do
  before do
    stub_const(
      'Rails',
      Class.new do
        def self.cache
          @cache ||= Object.new
        end
      end
    )
  end

  it 'uses global Rails.cache by default' do
    cache = described_class.new
    expect(cache.instance_variable_get(:@cache)).to eq(::Rails.cache)
    expect(cache).not_to be_fault_tolerant
  end

  it 'accepts a custom cache backend' do
    backend = Faulty::Cache::Mock.new
    cache = described_class.new(backend)
    cache.write('foo', 'bar')
    expect(backend.read('foo')).to eq('bar')
  end

  it 'can be marked as fault tolerant' do
    cache = described_class.new(fault_tolerant: true)
    expect(cache).to be_fault_tolerant
  end
end
