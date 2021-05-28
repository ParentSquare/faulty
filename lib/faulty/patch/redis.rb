# frozen_string_literal: true

require 'redis'

class Faulty
  module Patch
    # Patch Redis to run all network IO in a circuit
    #
    # This module is not required by default
    #
    # Pass a `:faulty` key into your redis connection options to enable
    # circuit protection. This hash is a hash of circuit options for the
    # internal circuit. The hash may also have a `:instance` key, which is the
    # faulty instance to create the circuit from. `Faulty.default` will be
    # used if no instance is given. The `:instance` key can also reference a
    # registered Faulty instance or a global constantso that it can be set
    # from config files. See {Patch.circuit_from_hash}.
    #
    # @example
    #   require 'faulty/patch/redis'
    #
    #   redis = Redis.new(url: 'redis://localhost:6379', faulty: {})
    #   redis.connect # raises Faulty::CircuitError if connection fails
    #
    #   # If the faulty key is not given, no circuit is used
    #   redis = Redis.new(url: 'redis://localhost:6379')
    #   redis.connect # not protected by a circuit
    #
    # @see Patch.circuit_from_hash
    module Redis
      include Base

      Patch.define_circuit_errors(self, ::Redis::BaseConnectionError)

      # Patches Redis to add the `:faulty` key
      def initialize(options = {})
        @faulty_circuit = Patch.circuit_from_hash(
          'redis',
          options[:faulty],
          errors: [::Redis::BaseConnectionError],
          patched_error_module: Faulty::Patch::Redis
        )

        super
      end

      # The initial connection is protected by a circuit
      def connect
        faulty_run { super }
      end

      # Reads/writes to redis are protected
      def io(&block)
        faulty_run { super }
      end
    end
  end
end

::Redis::Client.prepend(Faulty::Patch::Redis)
