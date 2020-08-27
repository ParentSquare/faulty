# frozen_string_literal: true

RSpec.describe Faulty::Scope do
  it 'converts symbol names to strings' do
    scope = described_class.new
    expect(scope.circuit(:test)).to eq(scope.circuit('test'))
  end
end
