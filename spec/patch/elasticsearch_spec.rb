# frozen_string_literal: true

RSpec.describe Faulty::Patch::Elasticsearch do
  let(:faulty) { Faulty.new(listeners: []) }

  let(:patched_module) { Faulty::Patch::Elasticsearch::PATCHED_MODULE }
  let(:good_url) { ENV.fetch('ELASTICSEARCH_URL', nil) }
  let(:bad_url) { 'localhost:9876' }
  let(:patched_good_client) { build_client(url: good_url, faulty: { instance: faulty }) }
  let(:patched_bad_client) { build_client(url: bad_url, faulty: { instance: faulty }) }
  let(:unpatched_good_client) { build_client(url: good_url) }
  let(:unpatched_bad_client) { build_client(url: bad_url) }
  let(:bad_client_unpatched_errors) do
    build_client(url: bad_url, faulty: { instance: faulty, patch_errors: false })
  end

  def build_client(**options)
    if Gem.loaded_specs['opensearch-ruby']
      ::OpenSearch::Client.new(options)
    else
      ::Elasticsearch::Client.new(options)
    end
  end

  it 'captures patched transport error' do
    expect { patched_bad_client.perform_request('GET', '_cluster/state') }
      .to raise_error do |error|
        expect(error).to be_a(patched_module::Transport::Transport::Error)
        expect(error.class).to eq(Faulty::Patch::Elasticsearch::Error::CircuitFailureError)
        expect(error).to be_a(Faulty::CircuitErrorBase)
        expect(error.cause).to be_a(
          if Gem.loaded_specs['elastic-transport']
            Elastic::Transport::Transport::Error
          else
            Faraday::ConnectionFailed
          end
        )
      end
    expect(faulty.circuit('elasticsearch').status.failure_rate).to eq(1)
  end

  it 'performs normal request for patched client' do
    expect(patched_good_client.perform_request('GET', '_cluster/health').body)
      .to have_key('status')
    expect(faulty.circuit('elasticsearch').status.failure_rate).to eq(0)
  end

  it 'performs normal request for unpatched client' do
    expect(unpatched_good_client.perform_request('GET', '_cluster/health').body)
      .to have_key('status')
    expect(faulty.circuit('elasticsearch').status.failure_rate).to eq(0)
  end

  it 'does not capture transport error for unpatched client' do
    expect { unpatched_bad_client.perform_request('GET', '_cluster/state') }
      .to raise_error(
        if Gem.loaded_specs['elastic-transport']
          Elastic::Transport::Transport::Error
        else
          Faraday::ConnectionFailed
        end
      )
    expect(faulty.circuit('elasticsearch').status.failure_rate).to eq(0)
  end

  it 'raises unpatched errors if configured to' do
    expect { bad_client_unpatched_errors.perform_request('GET', '_cluster/state') }
      .to raise_error do |error|
        expect(error.class).to eq(Faulty::CircuitFailureError)
        expect(error.cause).to be_a(
          if Gem.loaded_specs['elastic-transport']
            Elastic::Transport::Transport::Error
          else
            Faraday::ConnectionFailed
          end
        )
      end
    expect(faulty.circuit('elasticsearch').status.failure_rate).to eq(1)
  end

  it 'raises case-specific Elasticsearch errors' do
    # Force the client validation request
    patched_good_client.perform_request('GET', '/')
    faulty.circuit('elasticsearch').reset!

    expect { patched_good_client.perform_request('PUT', '') }
      .to raise_error do |error|
        expect(error).to be_a(patched_module::Transport::Transport::Errors::MethodNotAllowed)
        expect(error.class).to eq(Faulty::Patch::Elasticsearch::Errors::MethodNotAllowed::CircuitFailureError)
        expect(error).to be_a(Faulty::CircuitErrorBase)
        expect(error.cause.class).to eq(patched_module::Transport::Transport::Errors::MethodNotAllowed)
      end
    expect(faulty.circuit('elasticsearch').status.failure_rate).to eq(1)
  end

  it 'ignores 404 errors' do
    expect { patched_good_client.perform_request('GET', 'not_an_index') }
      .to raise_error do |error|
        expect(error.class).to eq(patched_module::Transport::Transport::Errors::NotFound)
      end
    expect(faulty.circuit('elasticsearch').status.failure_rate).to eq(0)
  end
end
