# frozen_string_literal: true

RSpec.describe Faulty::Scope do
  it 'does not combine string and symbol names for circuits' do
    scope = described_class.new
    expect(scope.circuit(:test)).not_to eq(scope.circuit('test'))
  end
end
