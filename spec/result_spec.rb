# frozen_string_literal: true

RSpec.describe Faulty::Result do
  let(:ok) { described_class.new(ok: 'foo') }
  let(:error) { described_class.new(error: StandardError.new) }

  it 'can be constructed with an ok' do
    expect(ok.ok?).to eq(true)
  end

  it 'can be constructed with an error' do
    expect(error.error?).to eq(true)
  end

  it 'raises an error if unchecked get is called' do
    expect { ok.get }.to raise_error(Faulty::UncheckedResultError)
  end

  it 'raises an error if unchecked error is called' do
    expect { error.error }.to raise_error(Faulty::UncheckedResultError)
  end

  it 'raises an error if get is called on error' do
    error.ok?
    expect { error.get }.to raise_error(Faulty::WrongResultError)
  end

  it 'raises an error if error is called on ok' do
    ok.ok?
    expect { ok.error }.to raise_error(Faulty::WrongResultError)
  end

  it 'raises an error if constructed with nothing' do
    expect { described_class.new }.to raise_error(ArgumentError)
  end

  it 'raises an error if constructed with both' do
    expect { described_class.new(ok: 'foo', error: StandardError.new) }.to raise_error(ArgumentError)
  end

  it 'does not confuse NOTHING with empty object' do
    expect(described_class.new(ok: {}).ok?).to eq(true)
  end

  it 'with ok #or_default passes value through' do
    expect(ok.or_default('fallback')).to eq('foo')
  end

  it 'with error #or_default returns alternate from argument' do
    expect(error.or_default('fallback')).to eq('fallback')
  end

  it 'with error #or_default returns alternate from block' do
    expect(error.or_default { 'fallback' }).to eq('fallback')
  end
end
