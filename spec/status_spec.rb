# frozen_string_literal: true

RSpec.describe Faulty::Status do
  let(:options) { Faulty::Circuit::Options.new({}) }

  it 'is closed by default' do
    expect(described_class.new(options: options)).to be_closed
  end

  context 'when state is closed' do
    subject(:status) { described_class.new(options: options, state: :closed) }

    it('is closed') { expect(status).to be_closed }
    it('is not open') { expect(status).not_to be_open }
    it('is not half_open') { expect(status).not_to be_half_open }
    it('can run') { expect(status.can_run?).to be(true) }
    it('is not locked_open') { expect(status).not_to be_locked_open }
    it('is not locked_closed') { expect(status).not_to be_locked_closed }
  end

  context 'when state is open and cool_down is not passed' do
    subject(:status) do
      described_class.new(options: options, state: :open, opened_at: Faulty.current_time)
    end

    it('is open') { expect(status).to be_open }
    it('is not closed') { expect(status).not_to be_closed }
    it('is not half_open') { expect(status).not_to be_half_open }
    it('cannot run') { expect(status.can_run?).to be(false) }
  end

  context 'when state is open and cool_down is passed' do
    subject(:status) do
      described_class.new(options: options, state: :open, opened_at: Faulty.current_time - 500)
    end

    it('is half_open') { expect(status).to be_half_open }
    it('is not open') { expect(status).not_to be_open }
    it('is not closed') { expect(status).not_to be_closed }
    it('can run') { expect(status.can_run?).to be(true) }
  end

  context 'when locked open' do
    subject(:status) { described_class.new(options: options, state: :closed, lock: :open) }

    it('is locked_open') { expect(status).to be_locked_open }
    it('cannot run') { expect(status.can_run?).to be(false) }
  end

  context 'when locked closed' do
    subject(:status) do
      described_class.new(
        options: options,
        state: :open,
        opened_at: Faulty.current_time,
        lock: :closed
      )
    end

    it('is locked_closed') { expect(status).to be_locked_closed }
    it('can run') { expect(status.can_run?).to be(true) }
  end

  context 'when sample size is too small' do
    subject(:status) { described_class.new(options: options, sample_size: 1, failure_rate: 0.99) }

    it('passes threshold') { expect(status.fails_threshold?).to be(false) }
  end

  context 'when failure rate is below rate_threshold' do
    subject(:status) { described_class.new(options: options, sample_size: 4, failure_rate: 0.4) }

    it('passes threshold') { expect(status.fails_threshold?).to be(false) }
  end

  context 'when failure rate is above rate_threshold' do
    subject(:status) { described_class.new(options: options, sample_size: 4, failure_rate: 0.6) }

    it('fails threshold') { expect(status.fails_threshold?).to be(true) }
  end

  context 'when failure rate equals rate_threshold' do
    subject(:status) { described_class.new(options: options, sample_size: 4, failure_rate: 0.5) }

    it('fails threshold') { expect(status.fails_threshold?).to be(true) }
  end

  it 'rejects invalid state' do
    expect { described_class.new(options: options, state: :blah) }
      .to raise_error(ArgumentError, /state must be a symbol in Faulty::Status::STATES/)
  end

  it 'rejects invalid lock' do
    expect { described_class.new(options: options, lock: :blah) }
      .to raise_error(ArgumentError, /lock must be a symbol in Faulty::Status::LOCKS/)
  end

  it 'requires opened_at if state is open' do
    expect { described_class.new(options: options, state: :open) }
      .to raise_error(ArgumentError, /opened_at is required if state is open/)
  end
end
