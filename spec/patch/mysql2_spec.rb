# frozen_string_literal: true

RSpec.describe 'Faulty::Patch::Mysql2', if: defined?(Mysql2) do # rubocop:disable RSpec/DescribeClass
  def new_client(opts = {})
    Mysql2::Client.new({
      username: ENV['MYSQL_USER'],
      password: ENV['MYSQL_PASSWORD'],
      host: ENV['MYSQL_HOST'],
      port: ENV['MYSQL_PORT'],
      socket: ENV['MYSQL_SOCKET']
    }.merge(opts))
  end

  def create_table(client, name)
    client.query("CREATE TABLE `#{db_name}`.`#{name}`(id INT NOT NULL)")
  end

  def trip_circuit
    client
    4.times do
      begin
        new_client(host: '127.0.0.1', port: 9999, faulty: { instance: faulty })
      rescue Mysql2::Error
        # Expect connection failure
      end
    end
  end

  let(:client) { new_client(database: db_name, faulty: { instance: faulty }) }
  let(:bad_client) { new_client(host: '127.0.0.1', port: 9999, faulty: { instance: faulty }) }
  let(:bad_unpatched_client) { new_client(host: '127.0.0.1', port: 9999) }
  let(:db_name) { SecureRandom.hex(6) }
  let(:faulty) { Faulty.new(listeners: [], circuit_defaults: { sample_threshold: 2 }) }

  before do
    new_client.query("CREATE DATABASE `#{db_name}`")
  end

  after do
    new_client.query("DROP DATABASE `#{db_name}`")
  end

  it 'captures connection error' do
    expect { bad_client.query('SELECT 1 FROM dual') }.to raise_error do |error|
      expect(error).to be_a(Faulty::Patch::Mysql2::CircuitError)
      expect(error.cause).to be_a(Mysql2::Error::ConnectionError)
    end
    expect(faulty.circuit('mysql2').status.failure_rate).to eq(1)
  end

  it 'does not capture unpatched client errors' do
    expect { bad_unpatched_client.query('SELECT 1 FROM dual') }.to raise_error(Mysql2::Error::ConnectionError)
    expect(faulty.circuit('mysql2').status.failure_rate).to eq(0)
  end

  it 'does not capture application errors' do
    expect { client.query('SELECT * FROM not_a_table') }.to raise_error(Mysql2::Error)
    expect(faulty.circuit('mysql2').status.failure_rate).to eq(0)
  end

  it 'successfully executes query' do
    create_table(client, 'test')
    client.query('INSERT INTO test VALUES(1)')
    expect(client.query('SELECT * FROM test').to_a).to eq([{ 'id' => 1 }])
    expect(faulty.circuit('mysql2').status.failure_rate).to eq(0)
  end

  it 'prevents additional queries when tripped' do
    trip_circuit
    expect { client.query('SELECT 1 FROM dual') }
      .to raise_error(Faulty::Patch::Mysql2::OpenCircuitError)
  end

  it 'allows COMMIT when tripped' do
    create_table(client, 'test')
    client.query('BEGIN')
    client.query('INSERT INTO test VALUES(1)')
    trip_circuit
    expect(client.query('COMMIT')).to eq(nil)
    expect { client.query('SELECT * FROM test') }
      .to raise_error(Faulty::Patch::Mysql2::OpenCircuitError)
    faulty.circuit('mysql2').reset!
    expect(client.query('SELECT * FROM test').to_a).to eq([{ 'id' => 1 }])
  end

  it 'allows ROLLBACK with leading comment when tripped' do
    create_table(client, 'test')
    client.query('BEGIN')
    client.query('INSERT INTO test VALUES(1)')
    trip_circuit
    expect(client.query('/* hi there */ ROLLBACK')).to eq(nil)
    expect { client.query('SELECT * FROM test') }
      .to raise_error(Faulty::Patch::Mysql2::OpenCircuitError)
    faulty.circuit('mysql2').reset!
    expect(client.query('SELECT * FROM test').to_a).to eq([])
  end
end
