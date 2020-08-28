# frozen_string_literal: true

RSpec.describe Faulty::Storage::FaultTolerantProxy do
  let(:notifier) { Faulty::Events::Notifier.new }

  let(:failing_storage) do
    Class.new do
      def method_missing(*_args) # rubocop:disable Style/MethodMissingSuper
        raise 'fail'
      end

      def respond_to_missing?(*_args)
        true
      end
    end
  end

  let(:fake_storage) do
    Class.new do
      def method_missing(*_args) # rubocop:disable Style/MethodMissingSuper
        'fake'
      end

      def respond_to_missing?(*_args)
        true
      end
    end
  end

  it 'delegates to storage when adding entry succeeds' do
    status = described_class.new(fake_storage.new, notifier: notifier)
      .entry(Faulty::Circuit.new('test'), Faulty.current_time, true)
    expect(status).to eq('fake')
  end

  it 'returns stub status when adding entry fails' do
    status = described_class.new(failing_storage.new, notifier: notifier)
      .entry(Faulty::Circuit.new('test'), Faulty.current_time, true)
    expect(status.stub).to eq(true)
  end

  it 'returns empty list when storage fails' do
    list = described_class.new(failing_storage.new, notifier: notifier).list
    expect(list).to eq([])
  end
end
