# frozen_string_literal: true

RSpec.describe Faulty do
  subject(:instance) { described_class.new(listeners: []) }

  after do
    # Reset the global Faulty instance
    # We don't want to expose a public method to do this
    # because it could cause concurrency errors, and confusion about what
    # exactly gets reset
    described_class.instance_variable_set(:@instances, nil)
    described_class.instance_variable_set(:@default_instance, nil)
  end

  it 'can be initialized with no args' do
    described_class.init
    expect(described_class.default).to be_a(described_class)
  end

  it 'gets options from the default instance' do
    described_class.init
    expect(described_class.options).to eq(described_class.default.options)
  end

  it '#default raises uninitialized error if #init not called' do
    expect { described_class.default }.to raise_error(Faulty::UninitializedError)
  end

  it 'raises error when initialized twice' do
    described_class.init
    expect { described_class.init }.to raise_error(Faulty::AlreadyInitializedError)
  end

  it '#default raises missing instance error if default not created' do
    described_class.init(nil)
    expect { described_class.default }.to raise_error(Faulty::MissingDefaultInstanceError)
  end

  it 'can rename the default instance on #init' do
    described_class.init(:foo)
    expect(described_class.default).to be_a(described_class)
    expect(described_class[:foo]).to eq(described_class.default)
  end

  it 'can be reinitialized if initialization fails' do
    expect { described_class.init(not_an_option: true) }.to raise_error(NameError)
    described_class.init
  end

  it 'registers a named instance' do
    described_class.init
    instance = described_class.new
    described_class.register(:new_instance, instance)
    expect(described_class[:new_instance]).to eq(instance)
  end

  it 'registers a named instance without default' do
    described_class.init(nil)
    instance = described_class.new
    described_class.register(:new_instance, instance)
    expect(described_class[:new_instance]).to eq(instance)
  end

  it 'memoizes named instances' do
    described_class.init
    instance1 = described_class.new
    instance2 = described_class.new
    expect(described_class.register(:named, instance1)).to eq(nil)
    expect(described_class.register(:named, instance2)).to eq(instance1)
    expect(described_class[:named]).to eq(instance1)
  end

  it 'delegates circuit to the default instance' do
    described_class.init(listeners: [])
    described_class.circuit('test').run { 'ok' }
    expect(described_class.default.list_circuits).to eq(['test'])
  end

  it 'lists the circuits from the default instance' do
    described_class.init(listeners: [])
    described_class.circuit('test').run { 'ok' }
    expect(described_class.list_circuits).to eq(['test'])
  end

  it 'gets the current timestamp' do
    Timecop.freeze(Time.new(2020, 1, 1, 0, 0, 0, '+00:00'))
    expect(described_class.current_time).to eq(1_577_836_800)
  end

  it 'memoizes circuits' do
    expect(instance.circuit('test')).to eq(instance.circuit('test'))
  end

  it 'keeps options passed to the first instance and ignores others' do
    instance.circuit('test', cool_down: 404)
    expect(instance.circuit('test', cool_down: 302).options.cool_down).to eq(404)
  end

  it 'passes options from itself to new circuits' do
    instance = described_class.new(
      circuit_defaults: { sample_threshold: 14, cool_down: 30 }
    )
    circuit = instance.circuit('test', cool_down: 10)
    expect(circuit.options.cache).to eq(instance.options.cache)
    expect(circuit.options.storage).to eq(instance.options.storage)
    expect(circuit.options.notifier).to eq(instance.options.notifier)
    expect(circuit.options.sample_threshold).to eq(14)
    expect(circuit.options.cool_down).to eq(10)
  end

  it 'converts symbol names to strings' do
    expect(instance.circuit(:test)).to eq(instance.circuit('test'))
  end

  it 'lists circuit names' do
    instance.circuit('test1').run { 'ok' }
    instance.circuit('test2').run { 'ok' }
    expect(instance.list_circuits).to match_array(%w[test1 test2])
  end

  it 'wraps non-fault-tolerant storage in AutoWire' do
    instance = described_class.new(storage: Faulty::Storage::Redis.new)
    expect(instance.options.storage).to be_a(Faulty::Storage::AutoWire)
  end

  it 'wraps non-fault-tolerant cache in AutoWire' do
    instance = described_class.new(cache: Faulty::Cache::Rails.new(nil))
    expect(instance.options.cache).to be_a(Faulty::Cache::AutoWire)
  end
end
