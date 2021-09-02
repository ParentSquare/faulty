# frozen_string_literal: true

class Faulty
  module Storage
    # A circuit wrapper for storage backends
    #
    # This class uses an internal {Circuit} to prevent the storage backend from
    # causing application issues. If the backend fails continuously, this
    # circuit will trip to prevent cascading failures. This internal circuit
    # uses an independent in-memory backend by default.
    class CircuitProxy
      attr_reader :options

      # Options for {CircuitProxy}
      #
      # @!attribute [r] circuit
      #   @return [Circuit] A replacement for the internal circuit. When
      #     modifying this, be careful to use only a reliable storage backend
      #     so that you don't introduce cascading failures.
      # @!attribute [r] notifier
      #   @return [Events::Notifier] A Faulty notifier to use for circuit
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

      # @param storage [Storage::Interface] The storage backend to wrap
      # @param options [Hash] Attributes for {Options}
      # @yield [Options] For setting options in a block
      def initialize(storage, **options, &block)
        @storage = storage
        @options = Options.new(options, &block)
      end

      %i[entry open reopen close lock unlock reset status history list].each do |method|
        define_method(method) do |*args|
          options.circuit.run { @storage.public_send(method, *args) }
        end
      end

      # This cache makes any storage fault tolerant, so this is always `true`
      #
      # @return [true]
      def fault_tolerant?
        @storage.fault_tolerant?
      end
    end
  end
end
