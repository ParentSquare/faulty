# frozen_string_literal: true

RSpec.describe Faulty::Events::FilterNotifier do
  let(:backend) { Faulty::Events::Notifier.new }

  it 'forwards all events by default' do
    filter = described_class.new(backend)
    expect(backend).to receive(:notify).with(:circuit_success, {})
    filter.notify(:circuit_success, {})
  end

  it 'forwards only given events' do
    filter = described_class.new(backend, events: %i[circuit_failure])
    expect(backend).to receive(:notify).with(:circuit_failure, {})
    filter.notify(:circuit_success, {})
    filter.notify(:circuit_failure, {})
  end

  it 'forwards all except exluded events' do
    filter = described_class.new(backend, exclude: %i[circuit_success])
    expect(backend).to receive(:notify).with(:circuit_failure, {})
    filter.notify(:circuit_success, {})
    filter.notify(:circuit_failure, {})
  end

  it 'forwards given events except excluded' do
    filter = described_class.new(backend, events: %i[circuit_failure circuit_success], exclude: %i[circuit_success])
    expect(backend).to receive(:notify).with(:circuit_failure, {})
    filter.notify(:circuit_success, {})
    filter.notify(:circuit_failure, {})
  end
end
