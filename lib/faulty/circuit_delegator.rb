# frozen_string_literal: true

class Faulty
  # A wrapper for any class. Method calls will be wrapped with a circuit.
  #
  # This class uses an internal {Circuit} to monitor the inner object for
  # failures. If the inner object continuously raises exceptions, this circuit
  # will trip to prevent cascading failures. The internal circuit uses an
  # independent in-memory backend by default.
  class CircuitDelegator < SimpleDelegator
    # Options for {CircuitDelegator}
    #
    # @!attribute [r] circuit
    #   @return [Circuit] A replacement for the internal circuit. When
    #     modifying this, be careful to use only a reliable storage backend
    #     so that you don't introduce cascading failures.
    # @!attribute [r] name
    #   @return [String] The name of the circuit. Defaults to the class name of
    #     the inner object. If `circuit` is given, this is ignored.
    # @!attribute [r] notifier
    #   @return [Events::Notifier] A Faulty notifier to use for circuit
    #     notifications. If `circuit` is given, this is ignored.
    Options = Struct.new(
      :circuit
    ) do
      include ImmutableOptions

      private

      def required
        %i[circuit]
      end
    end

    # @param obj [Object] The inner object to delegate to
    # @param options [Hash] Attributes for {Options}
    # @yield [Options] For setting options in a block
    def initialize(obj, **options, &block)
      @options = Options.new(options, &block)

      super(obj)
    end

    if RUBY_VERSION < '2.7'
      private_class_method def self.ruby2_keywords(*)
      end
    end

    ruby2_keywords def method_missing(m, *args, &block) # rubocop:disable Style/MissingRespondToMissing
      @options.circuit.run { super }
    end
  end
end
