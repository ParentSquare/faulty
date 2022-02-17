# frozen_string_literal: true

RSpec.describe Faulty::Deprecation do
  it 'prints note and sunset version' do
    expect(Kernel).to receive(:warn)
      .with('DEPRECATION: foo is deprecated and will be removed in 1.0 (Use bar)')
    described_class.deprecate(:foo, note: 'Use bar', sunset: '1.0')
  end

  it 'prints only subject' do
    expect(Kernel).to receive(:warn)
      .with('DEPRECATION: blah is deprecated')
    described_class.deprecate('blah')
  end

  it 'prints method deprecation' do
    expect(Kernel).to receive(:warn)
      .with('DEPRECATION: Faulty::Circuit#foo is deprecated and will be removed in 1.0 (Use bar)')
    described_class.method(Faulty::Circuit, :foo, note: 'Use bar', sunset: '1.0')
  end

  context 'with raise_errors!' do
    before { described_class.raise_errors! }

    after { described_class.raise_errors!(false) }

    it 'raises DeprecationError' do
      expect { described_class.deprecate('blah') }
        .to raise_error(Faulty::DeprecationError, 'blah is deprecated')
    end
  end

  context 'when silenced' do
    it 'does not surface deprecations' do
      expect(Kernel).not_to receive(:warn)
      described_class.silenced do
        described_class.deprecate('blah')
      end
    end
  end
end
