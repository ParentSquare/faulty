# frozen_string_literal: true

class Faulty
  module Patch
    # Patch Elasticsearch or Opensearch to run requests in a circuit
    #
    # Pass a `:faulty` key into your search client options to enable
    # circuit protection. See {Patch.circuit_from_hash} for the available
    # options.
    #
    # By default, all circuit errors raised by this patch inherit from
    # `::Opensearch::Transport::Transport::Error` or one of its subclasses
    # (for Elasticsearch, errors inherit from its similar error classes)
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
    module OpensearchBase
      include Base

      # Protect all elasticsearch requests
      def perform_request(*args)
        faulty_run { super }
      end

      def self.patch(base_mod, patch_mod) # rubocop:disable Metrics/MethodLength
        patch_mod.module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
          include OpensearchBase

          module Error; end
          module SnifferTimeoutError; end
          module ServerError; end

          MAPPED_ERRORS = {
            ::#{base_mod}::Transport::Transport::Error => Error,
            ::#{base_mod}::Transport::Transport::SnifferTimeoutError => SnifferTimeoutError,
            ::#{base_mod}::Transport::Transport::ServerError => ServerError
          }
          module Errors
            ::#{base_mod}::Transport::Transport::ERRORS.each do |_code, klass|
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
          private_constant :MAPPED_ERRORS

          def initialize(arguments = {}, &block)
            super

            errors = [::#{base_mod}::Transport::Transport::Error]
            errors.concat(@transport.host_unreachable_exceptions)

            @faulty_circuit = Patch.circuit_from_hash(
              'elasticsearch',
              arguments[:faulty],
              errors: errors,
              exclude: ::#{base_mod}::Transport::Transport::Errors::NotFound,
              patched_error_mapper: ERROR_MAPPER
            )
          end
        RUBY

        base_mod::Transport::Client.prepend(patch_mod)
      end
    end
  end
end
