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

  context 'when locked closed and reserved' do
    subject(:status) do
      described_class.new(
        options: options,
        state: :open,
        opened_at: Faulty.current_time,
        reserved_at: Faulty.current_time,
        lock: :closed
      )
    end

    it('is reserved') { expect(status).to be_reserved }
    it('can run regardless of reservation') { expect(status.can_run?).to be(true) }
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

  # Defends the invariant that `reserved_at` is meaningful only while
  # `state == :open`. A brief race in `Memory#close` can produce a snapshot
  # where `state` has flipped to `:closed` before `reserved_at` was reset;
  # normalizing here means downstream code (and event-listener payloads)
  # never has to special-case that transient shape.
  it 'normalizes reserved_at to nil when state is closed' do
    status = described_class.new(
      options: options,
      state: :closed,
      reserved_at: Faulty.current_time
    )
    expect(status.reserved_at).to be_nil
  end

  it 'preserves reserved_at when state is open' do
    reserved_at = Faulty.current_time
    status = described_class.new(
      options: options,
      state: :open,
      opened_at: Faulty.current_time,
      reserved_at: reserved_at
    )
    expect(status.reserved_at).to eq(reserved_at)
  end

  # Direct coverage for the Status#reserved? predicate. The case "state is
  # :closed with a non-nil reserved_at" is not tested here because
  # Status#finalize normalizes reserved_at to nil at construction time —
  # see 'normalizes reserved_at to nil when state is closed' above.
  describe '#reserved?' do
    # cool_down defaults to 300; pin current_time relative to that so the
    # boundary and expired examples are deterministic without Timecop.
    let(:now) { 1_000_000.0 }

    it 'is false when reserved_at is nil' do
      status = described_class.new(
        options: options,
        state: :open,
        opened_at: now,
        current_time: now
      )
      expect(status.reserved?).to be(false)
    end

    it 'is true when state is open and within cool_down' do
      status = described_class.new(
        options: options,
        state: :open,
        opened_at: now,
        reserved_at: now,
        current_time: now
      )
      expect(status.reserved?).to be(true)
    end

    it 'is false when the reservation has fully expired' do
      status = described_class.new(
        options: options,
        state: :open,
        opened_at: now - 1000,
        reserved_at: now - 1000,
        current_time: now
      )
      expect(status.reserved?).to be(false)
    end

    # Boundary: the predicate uses `>`, not `>=`, so a reservation exactly at
    # the cool_down expiry is considered expired (the next process may retry).
    it 'is false at the cool_down boundary' do
      status = described_class.new(
        options: options,
        state: :open,
        opened_at: now - options.cool_down,
        reserved_at: now - options.cool_down,
        current_time: now
      )
      expect(status.reserved?).to be(false)
    end
  end
end
