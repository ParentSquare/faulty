# frozen_string_literal: true

class Faulty
  # Used by Faulty instances to track and memoize Circuits
  #
  # Whenever a circuit is requested by `Faulty#circuit`, it calls
  # `#retrieve`. That will return a resolved circuit if there is one, or
  # otherwise, it will create a new circuit instance.
  #
  # Once any circuit is run, the circuit calls `#resolve`. That saves
  # the instance into the registry. Any calls to `#retrieve` after
  # the circuit is resolved will result in the same instance being returned.
  #
  # However, before a circuit is resolved, calling `Faulty#circuit` will result
  # in a new Circuit instance being created for every call. If multiples of
  # these call `resolve`, only the first one will "win" and be memoized.
  class CircuitRegistry
    def initialize(circuit_options)
      @circuit_options = circuit_options
      @circuit_options[:registry] = self
      @circuits = Concurrent::Map.new
    end

    # Retrieve a memoized circuit with the same name, or if none is yet
    # resolved, create a new one.
    #
    # @param name [String] The name of the circuit
    # @param options [Hash] Options for {Circuit::Options}
    # @yield [Circuit::Options] For setting options in a block
    # @return [Circuit] The new or memoized circuit
    def retrieve(name, options, &block)
      @circuits.fetch(name) do
        options = @circuit_options.merge(options)
        Circuit.new(name, **options, &block)
      end
    end

    # Save and memoize the given circuit as the "canonical" instance for
    # the circuit name
    #
    # If the name is already resolved, this will be ignored
    #
    # @return [Circuit, nil] If this circuit name is already resolved, the
    #   already-resolved circuit
    def resolve(circuit)
      @circuits.put_if_absent(circuit.name, circuit)
    end
  end
end
