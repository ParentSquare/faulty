# frozen_string_literal: true

RSpec.describe Faulty::Events::HoneybadgerListener do
  before do
    Honeybadger.configure do |c|
      c.backend = 'test'
      c.api_key = 'test'
    end
    Honeybadger::Backend::Test.notifications[:notices] = []
  end

  it 'notifies honeybadger of a circuit failure' do
    described_class.new.handle(:circuit_failure, {
      error: StandardError.new('fail'),
      circuit: Faulty::Circuit.new('test_circuit')
    })
    Honeybadger.flush
    notice = Honeybadger::Backend::Test.notifications[:notices].first
    expect(notice.error_message).to eq('StandardError: fail')
    expect(notice.context[:circuit]).to eq('test_circuit')
  end

  it 'notifies honeybadger of a cache failure' do
    described_class.new.handle(:cache_failure, {
      error: StandardError.new('fail'),
      action: :read,
      key: 'test'
    })
    Honeybadger.flush
    notice = Honeybadger::Backend::Test.notifications[:notices].first
    expect(notice.error_message).to eq('StandardError: fail')
    expect(notice.context[:action]).to eq(:read)
    expect(notice.context[:key]).to eq('test')
  end

  it 'notifies honeybadger of a storage failure' do
    described_class.new.handle(:storage_failure, {
      error: StandardError.new('fail'),
      action: :open,
      circuit: Faulty::Circuit.new('test_circuit')
    })
    Honeybadger.flush
    notice = Honeybadger::Backend::Test.notifications[:notices].first
    expect(notice.error_message).to eq('StandardError: fail')
    expect(notice.context[:action]).to eq(:open)
    expect(notice.context[:circuit]).to eq('test_circuit')
  end
end
