# frozen_string_literal: true

class Faulty
  module Storage
    # Automatically configure a storage backend
    #
    # Used by {Faulty#initialize} to setup sensible storage defaults
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

        def required
          %i[notifier]
        end
      end

      class << self
        # Wrap storage backends with sensible defaults
        #
        # If the cache is `nil`, create a new {Memory} storage.
        #
        # If a single storage backend is given and is fault tolerant, leave it
        # unmodified.
        #
        # If a single storage backend is given and is not fault tolerant, wrap it
        # in a {CircuitProxy} and a {FaultTolerantProxy}.
        #
        # If an array of storage backends is given, wrap each non-fault-tolerant
        # entry in a {CircuitProxy} and create a {FallbackChain}. If none of the
        # backends in the array are fault tolerant, also wrap the {FallbackChain}
        # in a {FaultTolerantProxy}.
        #
        # @todo Consider using a {FallbackChain} for non-fault-tolerant storages
        #   by default. This would fallback to a {Memory} storage. It would
        #   require a more conservative implementation of {Memory} that could
        #   limit the number of circuits stored. For now, users need to manually
        #   configure fallbacks.
        #
        # @param storage [Interface, Array<Interface>] A storage backed or array
        #   of storage backends to setup.
        # @param options [Hash] Attributes for {Options}
        # @yield [Options] For setting options in a block
        def wrap(storage, **options, &block)
          options = Options.new(options, &block)
          if storage.nil?
            Memory.new
          elsif storage.is_a?(Array)
            wrap_array(storage, options)
          elsif !storage.fault_tolerant?
            wrap_one(storage, options)
          else
            storage
          end
        end

        private

        # Wrap an array of storage backends in a fault-tolerant FallbackChain
        #
        # @param array [Array<Storage::Interface>] The array to wrap
        # @param options [Options]
        # @return [Storage::Interface] A fault-tolerant fallback chain
        def wrap_array(array, options)
          FaultTolerantProxy.wrap(FallbackChain.new(
            array.map { |s| s.fault_tolerant? ? s : circuit_proxy(s, options) },
            notifier: options.notifier
          ), notifier: options.notifier)
        end

        # Wrap one storage backend in fault-tolerant backends
        #
        # @param storage [Storage::Interface] The storage to wrap
        # @param options [Options]
        # @return [Storage::Interface] A fault-tolerant storage backend
        def wrap_one(storage, options)
          FaultTolerantProxy.new(
            circuit_proxy(storage, options),
            notifier: options.notifier
          )
        end

        # Wrap storage in a CircuitProxy
        #
        # @param storage [Storage::Interface] The storage to wrap
        # @param options [Options]
        # @return [CircuitProxy]
        def circuit_proxy(storage, options)
          CircuitProxy.new(storage, circuit: options.circuit, notifier: options.notifier)
        end
      end
    end
  end
end
