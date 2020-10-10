# frozen_string_literal: true

RSpec.describe Faulty::Cache::Default do
  subject(:cache) { described_class.new }

  it 'creates Null when neither Rails nor ActiveSupport is defined' do
    expect(cache.instance_variable_get(:@cache)).to be_a(Faulty::Cache::Null)
  end

  context 'when ActiveSupport is defined' do
    before do
      stub_const('ActiveSupport::Cache::MemoryStore', Faulty::Cache::Mock)
    end

    it 'forwards methods to internal cache' do
      cache.write('foo', 'bar')
      expect(cache.read('foo')).to eq('bar')
    end

    it 'uses ActiveSupport::Cache::MemoryStore' do
      wrapper = cache.instance_variable_get(:@cache)
      expect(wrapper).to be_a(Faulty::Cache::Rails)
      expect(wrapper.instance_variable_get(:@cache)).to be_a(ActiveSupport::Cache::MemoryStore)
    end

    context 'when Rails is defined' do
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

      it 'uses Rails.cache' do
        wrapper = cache.instance_variable_get(:@cache)
        expect(wrapper).to be_a(Faulty::Cache::Rails)
        expect(wrapper.instance_variable_get(:@cache)).to eq(::Rails.cache)
      end
    end
  end
end
