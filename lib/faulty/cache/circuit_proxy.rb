# frozen_string_literal: true

class Faulty
  module Cache
    # A circuit wrapper for cache backends
    #
    # This class uses an internal {Circuit} to prevent the cache backend from
    # causing application issues. If the backend fails continuously, this
    # circuit will trip to prevent cascading failures. This internal circuit
    # uses an independent in-memory backend by default.
    class CircuitProxy
      attr_reader :options

      # Options for {CircuitProxy}
      #
      # @!attribute [r] circuit
      #   @return [Circuit] A replacement for the internal circuit. When
      #     modifying this, be careful to use only a reliable circuit storage
      #     backend so that you don't introduce cascading failures.
      # @!attribute [r] notifier
      #   @return [Events::Notifier] A Faulty notifier to use for failure
      #     notifications. If `circuit` is given, this is ignored.
      Options = Struct.new(
        :circuit,
        :notifier
      ) do
        include ImmutableOptions

        private

        def finalize
          raise ArgumentError, 'The circuit or notifier option must be given' unless notifier || circuit

          self.circuit ||= Circuit.new(
            Faulty::Storage::CircuitProxy.name,
            notifier: Events::FilterNotifier.new(notifier, exclude: %i[circuit_success]),
            cache: Cache::Null.new
          )
        end
      end

      # @param cache [Cache::Interface] The cache backend to wrap
      # @param options [Hash] Attributes for {Options}
      # @yield [Options] For setting options in a block
      def initialize(cache, **options, &block)
        @cache = cache
        @options = Options.new(options, &block)
      end

      %i[read write].each do |method|
        define_method(method) do |*args|
          options.circuit.run { @cache.public_send(method, *args) }
        end
      end

      def fault_tolerant?
        @cache.fault_tolerant?
      end
    end
  end
end
