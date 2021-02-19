# frozen_string_literal: true

class Faulty
  module Cache
    # Automatically configure a cache backend
    #
    # Used by {Faulty#initialize} to setup sensible cache defaults
    class AutoWire
      # Options for {AutoWire}
      #
      # @!attribute [r] circuit
      #   @return [Circuit] A circuit for {CircuitProxy} if one is created.
      #     When modifying this, be careful to use only a reliable circuit
      #     storage backend so that you don't introduce cascading failures.
      # @!attribute [r] notifier
      #   @return [Events::Notifier] A Faulty notifier. If given, listeners are
      #     ignored.
      Options = Struct.new(
        :circuit,
        :notifier
      ) do
        include ImmutableOptions

        private

        def required
          %i[notifier]
        end
      end

      class << self
        # Wrap a cache backend with sensible defaults
        #
        # If the cache is `nil`, create a new {Default}.
        #
        # If the backend is not fault tolerant, wrap it in {CircuitProxy} and
        # {FaultTolerantProxy}.
        #
        # @param cache [Interface] A cache backend
        # @param options [Hash] Attributes for {Options}
        # @yield [Options] For setting options in a block
        def wrap(cache, **options, &block)
          options = Options.new(options, &block)
          if cache.nil?
            Cache::Default.new
          elsif cache.fault_tolerant?
            cache
          else
            Cache::FaultTolerantProxy.new(
              Cache::CircuitProxy.new(cache, circuit: options.circuit, notifier: options.notifier),
              notifier: options.notifier
            )
          end
        end
      end
    end
  end
end
