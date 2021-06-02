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

      class BusyError < ::Redis::CommandError
      end

      # Patches Redis to add the `:faulty` key
      def initialize(options = {})
        @faulty_circuit = Patch.circuit_from_hash(
          'redis',
          options[:faulty],
          errors: [
            ::Redis::BaseConnectionError,
            BusyError
          ],
          patched_error_module: Faulty::Patch::Redis
        )

        super
      end

      # The initial connection is protected by a circuit
      def connect
        faulty_run { super }
      end

      # Protect command calls
      def call(command)
        faulty_run { super }
      end

      # Protect command_loop calls
      def call_loop(command, timeout = 0)
        faulty_run { super }
      end

      # Protect pipelined commands
      def call_pipelined(commands)
        faulty_run { super }
      end

      # Inject specific error classes if client is patched
      #
      # This method does not raise errors, it returns them
      # as exception objects, so we simply modify that error if necessary and
      # return it.
      #
      # The call* methods above will then raise that error, so we are able to
      # capture it with faulty_run.
      def io(&block)
        return super unless @faulty_circuit

        reply = super
        if reply.is_a?(::Redis::CommandError)
          if reply.message.start_with?('BUSY')
            reply = BusyError.new(reply.message)
          end
        end

        reply
      end
    end
  end
end

::Redis::Client.prepend(Faulty::Patch::Redis)
