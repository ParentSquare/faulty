# frozen_string_literal: true

RSpec.describe Faulty::Patch::Redis do
  let(:faulty) { Faulty.new(listeners: []) }

  let(:bad_url) { 'redis://127.0.0.1:9876' }
  let(:bad_redis) { ::Redis.new(url: bad_url, faulty: { instance: faulty }) }
  let(:good_redis)  { ::Redis.new(faulty: { instance: faulty }) }
  let(:bad_unpatched_redis) do
    ::Redis.new(url: bad_url, faulty: { instance: faulty, patch_errors: false })
  end

  it 'captures connection error' do
    expect { bad_redis.client.connect }.to raise_error(Faulty::Patch::Redis::CircuitError)
    expect(faulty.circuit('redis').status.failure_rate).to eq(1)
  end

  it 'captures connection error during command' do
    expect { bad_redis.ping }.to raise_error(Faulty::Patch::Redis::CircuitError)
    expect(faulty.circuit('redis').status.failure_rate).to eq(1)
  end

  it 'does not capture command error' do
    expect { good_redis.foo }.to raise_error(Redis::CommandError)
    expect(faulty.circuit('redis').status.failure_rate).to eq(0)
  end

  it 'raises unpatched errors if specified' do
    expect { bad_unpatched_redis.ping }.to raise_error(Faulty::CircuitError)
    expect(faulty.circuit('redis').status.failure_rate).to eq(1)
  end
end
