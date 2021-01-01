# frozen_string_literal: true

RSpec.describe Faulty::Patch::Base do
  include described_class

  let(:circuit) { Faulty::Circuit.new('test', **options) }
  let(:options) { { cache: cache, storage: storage } }
  let(:storage) { Faulty::Storage::Memory.new }
  let(:cache) { Faulty::Cache::Mock.new }

  before { @faulty_circuit = circuit }

  it 'wraps block in a circuit' do
    expect { faulty_run { raise 'fail' } }.to raise_error(Faulty::CircuitFailureError)
  end

  it 'does not double wrap errors' do
    expect do
      faulty_run { faulty_run { raise 'fail' } }
    end.to raise_error(Faulty::CircuitFailureError)
    expect(circuit.status.sample_size).to eq(1)
  end
end
