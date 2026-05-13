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
    expect { listener.handle(:fake_event, circuit: 'test') }.not_to raise_error
  end

  it 'allows event with no handlers' do
    expect { listener.handle(:circuit_opened, circuit: 'test') }.not_to raise_error
  end

  it 'calls multiple handlers' do
    results = []
    listener.circuit_opened { |payload| results << payload }
    listener.circuit_opened { |payload| results << payload }
    listener.handle(:circuit_opened, circuit: 'test')
    expect(results).to contain_exactly({ circuit: 'test' }, { circuit: 'test' })
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
