# frozen_string_literal: true

require 'elasticsearch'

class Faulty
  module Patch
    # Patch Elasticsearch to run requests in a circuit
    #
    # This module is not required by default
    #
    # Pass a `:faulty` key into your Elasticsearch client options to enable
    # circuit protection. See {Patch.circuit_from_hash} for the available
    # options.
    #
    # By default, all circuit errors raised by this patch inherit from
    # `::Elasticsearch::Transport::Transport::Error`. One side effect of the way
    # this patch wraps errors is that `host_unreachable_exceptions` raised by
    # the inner transport adapters are converted into
    # `Elasticsearch::Transport::Transport::Error` instead of the transport
    # error type such as `Faraday::ConnectionFailed`.
    #
    # @example
    #   require 'faulty/patch/elasticsearch'
    #
    #   es = Elasticsearch::Client.new(url: 'http://localhost:9200', faulty: {})
    #   es.search(q: 'test') # raises Faulty::CircuitError if connection fails
    #
    #   # If the faulty key is not given, no circuit is used
    #   es = Elasticsearch::Client.new(url: 'http://localhost:9200', faulty: {})
    #   es.search(q: 'test') # not protected by a circuit
    #
    #   # With Searchkick
    #   Searchkick.client_options[:faulty] = {}
    #
    # @see Patch.circuit_from_hash
    module Elasticsearch
      include Base

      module Error; end
      module SnifferTimeoutError; end
      module ServerError; end

      # We will freeze this after adding the dynamic error classes
      MAPPED_ERRORS = { # rubocop:disable Style/MutableConstant
        ::Elasticsearch::Transport::Transport::Error => Error,
        ::Elasticsearch::Transport::Transport::SnifferTimeoutError => SnifferTimeoutError,
        ::Elasticsearch::Transport::Transport::ServerError => ServerError
      }

      module Errors
        ::Elasticsearch::Transport::Transport::ERRORS.each do |_code, klass|
          MAPPED_ERRORS[klass] = const_set(klass.name.split('::').last, Module.new)
        end
      end

      MAPPED_ERRORS.freeze
      MAPPED_ERRORS.each do |klass, mod|
        Patch.define_circuit_errors(mod, klass)
      end

      ERROR_MAPPER = lambda do |error_name, cause, circuit|
        MAPPED_ERRORS.fetch(cause&.class, Error).const_get(error_name).new(cause&.message, circuit)
      end
      private_constant :ERROR_MAPPER, :MAPPED_ERRORS

      def initialize(arguments = {}, &block)
        super

        errors = [::Elasticsearch::Transport::Transport::Error]
        errors.concat(@transport.host_unreachable_exceptions)

        @faulty_circuit = Patch.circuit_from_hash(
          'elasticsearch',
          arguments[:faulty],
          errors: errors,
          exclude: ::Elasticsearch::Transport::Transport::Errors::NotFound,
          patched_error_mapper: ERROR_MAPPER
        )
      end

      # Protect all elasticsearch requests
      def perform_request(*args)
        faulty_run { super }
      end
    end
  end
end

module Elasticsearch
  module Transport
    class Client
      prepend(Faulty::Patch::Elasticsearch)
    end
  end
end
