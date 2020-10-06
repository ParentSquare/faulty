# frozen_string_literal: true

require 'connection_pool'

RSpec.describe Faulty::Storage::Redis do
  let(:circuit) { Faulty::Circuit.new('test') }

  it 'accepts a connection pool' do
    pool = ConnectionPool.new(size: 2, timeout: 1) { Redis.new(timeout: 1) }
    storage = described_class.new(client: pool)
    storage.entry(circuit, Faulty.current_time, true)
    expect(storage.history(circuit).size).to eq(1)
  end
end
