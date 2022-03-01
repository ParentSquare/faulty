# frozen_string_literal: true

require 'elasticsearch'
require 'faulty/patch/opensearch_base'

class Faulty
  module Patch
    # Patch Elasticsearch to run requests in a circuit
    #
    # @example
    #   require 'faulty/patch/elasticsearch'
    #   es = Opensearch::Client.new(url: 'http://localhost:9200', faulty: {})
    #
    # @see OpensearchBase For more details
    module Elasticsearch
      OpensearchBase.patch(::Elasticsearch, self)
    end
  end
end
