# frozen_string_literal: true

RSpec.describe Faulty::Events::Notifier do
  let(:listener_class) do
    Class.new do
      attr_reader :events

      def initialize
        @events = []
      end

      def handle(event, payload)
        @events << [event, payload]
      end
    end
  end

  let(:failing_class) do
    Class.new do
      def self.name
        'Failing'
      end

      def handle(_event, _payload)
        raise 'fail'
      end
    end
  end

  it 'calls handle for each listener' do
    listeners = [listener_class.new, listener_class.new]
    notifier = described_class.new(listeners)
    notifier.notify(:circuit_closed, {})
    expect(listeners[0].events).to eq([[:circuit_closed, {}]])
    expect(listeners[1].events).to eq([[:circuit_closed, {}]])
  end

  it 'suppresses and prints errors' do
    notifier = described_class.new([failing_class.new])
    expect { notifier.notify(:circuit_opened, {}) }
      .to output("Faulty listener Failing crashed: fail\n").to_stderr
  end

  it 'raises error for incorrect event' do
    notifier = described_class.new
    expect { notifier.notify(:foo, {}) }.to raise_error(ArgumentError)
  end
end
