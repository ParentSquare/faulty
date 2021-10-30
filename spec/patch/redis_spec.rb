# frozen_string_literal: true

RSpec.describe Faulty::Patch::Redis do
  let(:faulty) { Faulty.new(listeners: []) }

  let(:bad_url) { 'redis://127.0.0.1:9876' }
  let(:bad_redis) { ::Redis.new(url: bad_url, faulty: { instance: faulty }) }
  let(:good_redis) { ::Redis.new(faulty: { instance: faulty }) }
  let(:bad_unpatched_redis) { ::Redis.new(url: bad_url) }
  let(:bad_redis_unpatched_errors) do
    ::Redis.new(url: bad_url, faulty: { instance: faulty, patch_errors: false })
  end

  it 'captures connection error' do
    expect { bad_redis.client.connect }.to raise_error(Faulty::Patch::Redis::CircuitError)
    expect(faulty.circuit('redis').status.failure_rate).to eq(1)
  end

  it 'does not capture connection error if no circuit' do
    expect { bad_unpatched_redis.client.connect }.to raise_error(::Redis::BaseConnectionError)
    expect(faulty.circuit('redis').status.failure_rate).to eq(0)
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
    expect { bad_redis_unpatched_errors.ping }.to raise_error(Faulty::CircuitError)
    expect(faulty.circuit('redis').status.failure_rate).to eq(1)
  end

  context 'with busy Redis instance' do
    let(:busy_thread) do
      begin
        thread = Thread.new do
          begin
            ::Redis.new(read_timeout: 10).eval("while true do\n end")
          rescue Redis::CommandError
            # Ok when script is killed
          end
        end
        # Try to force new thread to be scheduled
        sleep 0.5
        thread
      end
    end

    before do
      busy_thread
    end

    after do
      begin
        ::Redis.new(read_timeout: 10).call(%w[SCRIPT KILL])
      rescue Redis::CommandError
        # Ok if no script is running
      end
      busy_thread.join
    end

    it 'captures busy command error' do
      expect { good_redis.ping }.to raise_error do |error|
        expect(error).to be_a(Faulty::Patch::Redis::CircuitError)
        expect(error.cause).to be_a(Faulty::Patch::Redis::BusyError)
        expect(error.cause.message).to eq(
          'BUSY Redis is busy running a script. You can only call SCRIPT KILL or SHUTDOWN NOSAVE.'
        )
      end

      expect(faulty.circuit('redis').status.failure_rate).to be > 0
    end
  end
end
