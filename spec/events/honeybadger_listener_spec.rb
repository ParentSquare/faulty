# frozen_string_literal: true

RSpec.describe Faulty::Events::HoneybadgerListener do
  let(:circuit) { Faulty::Circuit.new('test_circuit') }
  let(:error) { StandardError.new('fail') }
  let(:notice) do
    Honeybadger.flush
    Honeybadger::Backend::Test.notifications[:notices].first
  end

  before do
    skip 'Honeybadger only supports >= Ruby 2.4' unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.4')
    require 'honeybadger/ruby'

    Honeybadger.configure do |c|
      c.backend = 'test'
      c.api_key = 'test'
    end
    Honeybadger::Backend::Test.notifications[:notices] = []
  end

  it 'notifies honeybadger of a circuit failure' do
    described_class.new.handle(:circuit_failure, { error: error, circuit: circuit })
    expect(notice.error_message).to eq('StandardError: fail')
    expect(notice.context[:circuit]).to eq('test_circuit')
  end

  it 'notifies honeybadger of a circuit open' do
    described_class.new.handle(:circuit_opened, { error: error, circuit: circuit })
    expect(notice.error_message).to eq('StandardError: fail')
    expect(notice.context[:circuit]).to eq('test_circuit')
  end

  it 'notifies honeybadger of a circuit reopen' do
    described_class.new.handle(:circuit_reopened, { error: error, circuit: circuit })
    expect(notice.error_message).to eq('StandardError: fail')
    expect(notice.context[:circuit]).to eq('test_circuit')
  end

  it 'notifies honeybadger of a cache failure' do
    described_class.new.handle(:cache_failure, { error: error, action: :read, key: 'test' })
    expect(notice.error_message).to eq('StandardError: fail')
    expect(notice.context[:action]).to eq(:read)
    expect(notice.context[:key]).to eq('test')
  end

  it 'notifies honeybadger of a storage failure' do
    described_class.new.handle(:storage_failure, { error: error, action: :open, circuit: circuit })
    expect(notice.error_message).to eq('StandardError: fail')
    expect(notice.context[:action]).to eq(:open)
    expect(notice.context[:circuit]).to eq('test_circuit')
  end
end
