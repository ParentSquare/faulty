# frozen_string_literal: true

class Faulty
  # The base error for all Faulty errors
  class FaultyError < StandardError; end

  # Raised if using the global Faulty object without initializing it
  class UninitializedError < FaultyError
    def initialize(message = nil)
      message ||= 'Faulty is not initialized'
      super(message)
    end
  end

  # Raised if {Faulty.init} is called multiple times
  class AlreadyInitializedError < FaultyError
    def initialize(message = nil)
      message ||= 'Faulty is already initialized'
      super(message)
    end
  end

  # Raised if getting the default instance without initializing one
  class MissingDefaultInstanceError < FaultyError
    def initialize(message = nil)
      message ||= 'No default instance. Create one with init or get your instance with Faulty[:name]'
      super(message)
    end
  end

  # The base error for all errors raised during circuit runs
  #
  class CircuitError < FaultyError
    attr_reader :circuit

    def initialize(message, circuit)
      message ||= %(circuit error for "#{circuit.name}")
      @circuit = circuit

      super(message)
    end
  end

  # Raised when running a circuit that is already open
  class OpenCircuitError < CircuitError; end

  # Raised when an error occurred while running a circuit
  #
  # The `cause` will always be set and will be the internal error
  #
  # @see CircuitTrippedError For when the circuit is tripped
  class CircuitFailureError < CircuitError; end

  # Raised when an error occurred causing a circuit to close
  #
  # The `cause` will always be set and will be the internal error
  class CircuitTrippedError < CircuitError; end

  # Raised if calling get or error on a result without checking it
  class UncheckedResultError < FaultyError; end

  # Raised if getting the wrong result type.
  #
  # For example, calling get on an error result will raise this
  class WrongResultError < FaultyError; end
end
