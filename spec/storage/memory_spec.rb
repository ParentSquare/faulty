# frozen_string_literal: true

RSpec.describe Faulty::Storage::Memory do
  let(:circuit) { Faulty::Circuit.new('test') }

  it 'rotates entries after max_sample_size' do
    storage = described_class.new(max_sample_size: 3)
    3.times { |i| storage.entry(circuit, i, true, nil) }
    expect(storage.history(circuit).map { |h| h[0] }).to eq([0, 1, 2])
    storage.entry(circuit, 9, true, nil)
    expect(storage.history(circuit).map { |h| h[0] }).to eq([1, 2, 9])
  end

  it 'clears circuits and list' do
    storage = described_class.new
    storage.entry(circuit, Faulty.current_time, true, nil)
    storage.clear
    expect(storage.list).to eq([])
    expect(storage.history(circuit)).to eq([])
  end

  # Preserving reserved_at across reopen is load-bearing for half-open
  # exclusivity. If a late-arriving process E read status while reserved_at
  # was still nil (before the winning process A reserved), and A then
  # reserved, ran, failed, and reopened, E's CAS(nil -> T_E) would
  # incorrectly succeed if reopen cleared reserved_at to nil. The current
  # value (the reservation A made) must survive reopen so E's CAS sees a
  # mismatch and skips.
  it 'does not clear reserved_at on reopen' do
    storage = described_class.new
    storage.open(circuit, 100.0)
    storage.reserve(circuit, 100.0, nil)
    storage.reopen(circuit, 200.0, 100.0)
    expect(storage.status(circuit).reserved_at).to eq(100.0)
  end

  # The threaded test in spec/circuit_spec.rb only exercises the
  # Status#reserved? short-circuit — the loser bails before ever calling
  # storage.reserve. This direct CAS test exercises
  # Concurrent::Atom#compare_and_set and would fail if Memory#reserve
  # regressed to a non-atomic implementation.
  it 'reserves the circuit once when called concurrently', :concurrency do
    storage = described_class.new
    result = concurrently(50) do
      storage.reserve(circuit, Faulty.current_time, nil)
    end
    expect(result.count { |r| r }).to eq(1)
  end
end
