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
end
