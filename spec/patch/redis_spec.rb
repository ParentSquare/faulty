# frozen_string_literal: true

RSpec.describe Faulty::Patch::Redis do
  let(:faulty) { Faulty.new(listeners: []) }

  let(:bad_url) { 'redis://127.0.0.1:9876' }
  let(:bad_redis) { ::Redis.new(opts(url: bad_url, faulty: { instance: faulty })) }
  let(:good_redis) { ::Redis.new(opts(faulty: { instance: faulty })) }
  let(:bad_unpatched_redis) { ::Redis.new(opts(url: bad_url)) }
  let(:bad_redis_unpatched_errors) do
    ::Redis.new(opts(url: bad_url, faulty: { instance: faulty, patch_errors: false }))
  end
  let(:timeout) { 1 }

  def opts(faulty: nil, **opts)
    if Redis::VERSION.to_f >= 5
      { custom: { faulty: faulty }, timeout: timeout, **opts }
    else
      { faulty: faulty, timeout: timeout, **opts }
    end
  end

  def connect(redis)
    if Redis::VERSION.to_f >= 5
      redis.connect
    else
      redis.client.connect
    end
  end

  def faulty_cause(error)
    if Redis::VERSION.to_f >= 5
      error.cause.cause
    else
      error.cause
    end
  end

  it 'captures connection error' do
    expect { connect(bad_redis) }.to raise_error do |error|
      expect(error).to be_a(::Redis::BaseConnectionError)
      if Redis::VERSION.to_f >= 5
        expect(faulty_cause(error)).to be_a(Faulty::Patch::Redis::CircuitError)
      else
        expect(error).to be_a(Faulty::Patch::Redis::CircuitError)
      end
    end
    expect(faulty.circuit('redis').status.failure_rate).to eq(1)
  end

  it 'does not capture connection error if no circuit' do
    expect { connect(bad_unpatched_redis) }.to raise_error(::Redis::BaseConnectionError)
    expect(faulty.circuit('redis').status.failure_rate).to eq(0)
  end

  it 'captures connection error during command' do
    expect { bad_redis.ping }.to raise_error do |error|
      expect(error).to be_a(::Redis::BaseConnectionError)
      expect(faulty_cause(error)).to be_a(Faulty::Patch::Redis::CircuitError)
    end
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
      event = Concurrent::Event.new
      thread = Thread.new do
        begin
          event.wait(1)
          # This thread will block here until killed
          ::Redis.new(timeout: 10).eval("while true do\n end")
        rescue Redis::CommandError
          # Ok when script is killed
        end
      end
      # Wait for the new thread to be scheduled
      # and for the Redis command to be executed
      event.set
      sleep(0.5)
      thread
    end
    let(:timeout) { 3 }

    before do
      good_redis
      busy_thread
    end

    after do
      begin
        ::Redis.new(timeout: 10).call(%w[SCRIPT KILL])
      rescue Redis::CommandError
        # Ok if no script is running
      end
      busy_thread.join
    end

    it 'captures busy command error' do
      expect { good_redis.ping }.to raise_error do |error|
        expect(error).to be_a(::Redis::BaseConnectionError)
        expect(faulty_cause(error)).to be_a(Faulty::Patch::Redis::BusyError)
        expect(faulty_cause(error).message).to match(
          /BUSY Redis is busy running a script. You can only call SCRIPT KILL or SHUTDOWN NOSAVE/
        )
      end

      expect(faulty.circuit('redis').status.failure_rate).to be > 0
    end
  end
end
