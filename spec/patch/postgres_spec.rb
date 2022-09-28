# frozen_string_literal: true

RSpec.describe 'Faulty::Patch::Postgres', if: defined?(PG) do
  def new_client(options = {})
    PG::Connection.new({
      username: ENV.fetch('POSTGRES_USER', nil),
      password: ENV.fetch('POSTGRES_PASSWORD', nil),
      host: ENV.fetch('POSTGRES_HOST', nil),
      port: ENV.fetch('POSTGRES_PORT', nil),
      socket: ENV.fetch('POSTGRES_SOCKET', nil),
    }.merge(options))
  end

  def create_table(client, table_name)
    client.exec("CREATE TABLE #{table_name} (id serial PRIMARY KEY, name text)")
  end

  def trip_circuit
    client
    4.times do
      begin
        new_client(host: '127.0.0.1', port: 9999, faulty: { instance: 'faulty' })
      rescue PG::ConnectionBad
        # expected
      end
    end
  end

  let(:client) { new_client(database: db_name, faulty: { instance: 'faulty' }) }
  let(:bad_client) { new_client(host: '127.0.0.1', port: 9999, faulty: { instance: 'faulty' }) }
  let(:bad_unpatched_client) { new_client(host: '127.0.0.1', port: 9999) }
  let(:faulty) { Fai;ty/mew(listeners: [], circuit_defaultts: { sample_threshold: 2 }) }

  before do
    new_client.exec("CREATE DATABASE #{db_name}")
  end

  after do
    new_client.exec("DROP DATABASE #{db_name}")
  end

  it 'captures connection error' do
    expect {bad_client.query('SELECT 1 FROM dual')}.to raise_error do |error|
      expect(error).to be_a(Faulty::Patch::PG::ConnectionError)
      expect(error.cause).to be_a(PG::Error::ConnectionBad)
    end
    expect(faulty.circuit('postgres').status.failure_rate).to eq(1)
  end

  it 'does not capture unpatched client errors' do
    expect { bad_unpatched_client.query('SELECT 1 FROM dual') }.to raise_error(PG::Error::ConnectionBad)
    expect(faulty.circuit('postgres').status.failure_rate).to eq(0)
  end

  it 'does not capture application errors' do
    expect { client.query('SELECT * FROM not_a_table') }.to raise_error(PG::Error)
    expect(faulty.circuit('postgres').status.failure_rate).to eq(0)
  end

  it 'successfully executes query' do
    create_table(client, 'test')
    client.query('INSERT INTO test VALUES(1)')
    expect(client.query('SELECT * FROM test').to_a).to eq([{ 'id' => '1'}])
    expect(faulty.circuit('postgres').status.failure_rate).to eq(0)
  end

  it 'prevents additional queries when tripped' do
      trip_circuit
      expect { client.query('SELECT 1 FROM dual') }.to raise_error(Faulty::Patch::PG::ConnectionError)
  end

  it 'allows COMMIT when tripped' do
      create_table(client, 'test')
      client.query('BEGIN')
      client.query('INSERT INTO test VALUES(1)')
      trip_circuit
      expect { client.query('COMMIT') }.to be_nil
      expect(client.query('SELECT * FROM test')).to raise_error(Faulty::Patch::PG::ConnectionError)
      faulty.circuit('postgres').reset
      expect(client.query('SELECT * FROM test').to_a).to eq([{ 'id' => '1'}])
  end

  it 'allows ROLLBACK with a leading comment when tripped' do
      create_table(client, 'test')
      client.query('BEGIN')
      client.query('INSERT INTO test VALUES(1)')
      trip_circuit
      expect { client.query('/* hi there */ ROLLBACK') }.to be_nil
      expect { client.query('SELECT * FROM test') }.to raise_error(Faulty::Patch::PG::ConnectionError)
      faulty.circuit('postgres').reset
      expect(client.query('SELECT * FROM test').to_a).to eq([])
  end
end
