# frozen_string_literal: true

require 'redis'

class Faulty
  module Patch
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
          patched_error_mapper: Faulty::Patch::Redis
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
        if reply.is_a?(::Redis::CommandError) && reply.message.start_with?('BUSY')
          reply = BusyError.new(reply.message)
        end

        reply
      end
    end
  end
end

class Redis
  class Client
    prepend(Faulty::Patch::Redis)
  end
end
