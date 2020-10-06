# frozen_string_literal: true

RSpec.describe Faulty::Events::CallbackListener do
  subject(:listener) { described_class.new }

  it 'calls handler with event payload' do
    result = nil
    listener.circuit_opened { |payload| result = payload }
    listener.handle(:circuit_opened, circuit: 'test')
    expect(result[:circuit]).to eq('test')
  end

  it 'does nothing for unknown event' do
    listener.handle(:fake_event, circuit: 'test')
  end

  it 'allows event with no handlers' do
    listener.handle(:circuit_opened, circuit: 'test')
  end

  it 'calls multiple handlers' do
    results = []
    listener.circuit_opened { |payload| results << payload }
    listener.circuit_opened { |payload| results << payload }
    listener.handle(:circuit_opened, circuit: 'test')
    expect(results).to match_array([{ circuit: 'test' }, { circuit: 'test' }])
  end

  it 'can register listeners in initialize block' do
    result = nil
    listener = described_class.new do |events|
      events.circuit_closed do |payload|
        result = payload
      end
    end

    listener.handle(:circuit_closed, circuit: 'test')
    expect(result[:circuit]).to eq('test')
  end
end
