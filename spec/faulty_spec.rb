# frozen_string_literal: true

RSpec.describe Faulty do
  after do
    # Reset the global Faulty instance
    # We don't want to expose a public method to do this
    # because it could cause concurrency errors, and confusion about what
    # exactly gets reset
    described_class.instance_variable_set(:@scopes, nil)
    described_class.instance_variable_set(:@default_scope, nil)
  end

  it 'can be initialized with no args' do
    described_class.init
    expect(described_class.default).to be_a(Faulty::Scope)
  end

  it 'gets options from the default scope' do
    described_class.init
    expect(described_class.options).to eq(described_class.default.options)
  end

  it '#default raises uninitialized error if #init not called' do
    expect { described_class.default }.to raise_error(Faulty::UninitializedError)
  end

  it '#default raises missing scope error if default not created' do
    described_class.init(nil)
    expect { described_class.default }.to raise_error(Faulty::MissingDefaultScopeError)
  end

  it 'can rename the default scope on #init' do
    described_class.init(:foo)
    expect(described_class.default).to be_a(Faulty::Scope)
    expect(described_class[:foo]).to eq(described_class.default)
  end

  it 'can be reinitialized if initialization fails' do
    expect { described_class.init(not_an_option: true) }.to raise_error(NameError)
    described_class.init
  end

  it 'registers a named scope' do
    described_class.init
    scope = Faulty::Scope.new
    described_class.register(:new_scope, scope)
    expect(described_class[:new_scope]).to eq(scope)
  end

  it 'registers a named scope without default' do
    described_class.init(nil)
    scope = Faulty::Scope.new
    described_class.register(:new_scope, scope)
    expect(described_class[:new_scope]).to eq(scope)
  end

  it 'memoizes named scopes' do
    described_class.init
    scope1 = Faulty::Scope.new
    scope2 = Faulty::Scope.new
    expect(described_class.register(:named, scope1)).to eq(nil)
    expect(described_class.register(:named, scope2)).to eq(scope1)
    expect(described_class[:named]).to eq(scope1)
  end

  it 'delegates circuit to the default scope' do
    described_class.init(listeners: [])
    described_class.circuit('test').run { 'ok' }
    expect(described_class.default.list_circuits).to eq(['test'])
  end

  it 'lists the circuits from the default scope' do
    described_class.init(listeners: [])
    described_class.circuit('test').run { 'ok' }
    expect(described_class.list_circuits).to eq(['test'])
  end

  it 'gets the current timestamp' do
    Timecop.freeze(Time.new(2020, 1, 1, 0, 0, 0, '+00:00'))
    expect(described_class.current_time).to eq(1_577_836_800)
  end
end
