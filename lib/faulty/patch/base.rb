# frozen_string_literal: true

class Faulty
  module Patch
    # Can be included in patch modules to provide common functionality
    #
    # The patch needs to set `@faulty_circuit`
    #
    # @example
    #   module ThingPatch
    #     include Faulty::Patch::Base
    #
    #     def initialize(options = {})
    #       @faulty_circuit = Faulty::Patch.circuit_from_hash('thing', options[:faulty])
    #     end
    #
    #     def do_something
    #       faulty_run { super }
    #     end
    #   end
    #
    #   Thing.prepend(ThingPatch)
    module Base
      # Run a block wrapped by `@faulty_circuit`
      #
      # If `@faulty_circuit` is not set, the block will be run with no
      # circuit.
      #
      # Nested calls to this method will only cause the circuit to be triggered
      # once.
      #
      # @yield A block to run inside the circuit
      # @return The block return value
      def faulty_run
        faulty_running_key = "faulty_running_#{object_id}"
        return yield unless @faulty_circuit
        return yield if Thread.current[faulty_running_key]

        Thread.current[faulty_running_key] = true
        @faulty_circuit.run { yield }
      ensure
        Thread.current[faulty_running_key] = false
      end
    end
  end
end
