# frozen_string_literal: true

module Faulty
  # The base error for all Faulty errors
  class FaultyError < StandardError; end

  class CircuitError < FaultyError
    attr_reader :circuit

    def initialize(message, circuit)
      message ||= "circuit=#{circuit.name}"
      @circuit = circuit

      super(message)
    end
  end

  # Raised when running a circuit that is already open
  class OpenCircuitError < CircuitError; end

  # Raised when an error occurred while running a circuit
  #
  # @see CircuitTrippedError For when the circuit is tripped
  class CircuitFailureError < CircuitError; end

  # Raised when an error occurred causing a circuit to close
  class CircuitTrippedError < CircuitError; end
end
