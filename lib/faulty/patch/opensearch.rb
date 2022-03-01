# frozen_string_literal: true

require 'opensearch-ruby'
require 'faulty/patch/opensearch_base'

class Faulty
  module Patch
    # Patch Opensearch to run requests in a circuit
    #
    # This module is not required by default
    #
    # @example
    #   require 'faulty/patch/opensearch'
    #   os = Opensearch::Client.new(url: 'http://localhost:9200', faulty: {})
    #
    # @see OpensearchBase For more details
    module Opensearch
      OpensearchBase.patch(::Opensearch, self)
    end
  end
end
