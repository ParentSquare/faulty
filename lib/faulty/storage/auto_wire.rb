# frozen_string_literal: true

class Faulty
  module Storage
    # Automatically configure a storage backend
    #
    # Used by {Faulty#initialize} to setup sensible storage defaults
    class AutoWire
      extend Forwardable

      # Options for {AutoWire}
      Options = Struct.new(
        :notifier
      ) do
        include ImmutableOptions

        private

        def required
          %i[notifier]
        end
      end

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
      def initialize(storage, **options, &block)
        @options = Options.new(options, &block)
        @storage = if storage.nil?
          Memory.new
        elsif storage.is_a?(Array)
          wrap_array(storage)
        elsif !storage.fault_tolerant?
          wrap_one(storage)
        else
          storage
        end

        freeze
      end

      # @!method entry(circuit, time, success)
      #   (see Faulty::Storage::Interface#entry)
      #
      # @!method open(circuit, opened_at)
      #   (see Faulty::Storage::Interface#open)
      #
      # @!method reopen(circuit, opened_at, previous_opened_at)
      #   (see Faulty::Storage::Interface#reopen)
      #
      # @!method close(circuit)
      #   (see Faulty::Storage::Interface#close)
      #
      # @!method lock(circuit, state)
      #   (see Faulty::Storage::Interface#lock)
      #
      # @!method unlock(circuit)
      #   (see Faulty::Storage::Interface#unlock)
      #
      # @!method reset(circuit)
      #   (see Faulty::Storage::Interface#reset)
      #
      # @!method status(circuit)
      #   (see Faulty::Storage::Interface#status)
      #
      # @!method history(circuit)
      #   (see Faulty::Storage::Interface#history)
      #
      # @!method list
      #   (see Faulty::Storage::Interface#list)
      #
      def_delegators :@storage,
        :entry, :open, :reopen, :close, :lock,
        :unlock, :reset, :status, :history, :list

      def fault_tolerant?
        true
      end

      private

      # Wrap an array of storage backends in a fault-tolerant FallbackChain
      #
      # @return [Storage::Interface] A fault-tolerant fallback chain
      def wrap_array(array)
        FaultTolerantProxy.wrap(FallbackChain.new(
          array.map { |s| s.fault_tolerant? ? s : CircuitProxy.new(s, notifier: @options.notifier) },
          notifier: @options.notifier
        ), notifier: @options.notifier)
      end

      def wrap_one(storage)
        FaultTolerantProxy.new(
          CircuitProxy.new(storage, notifier: @options.notifier),
          notifier: @options.notifier
        )
      end
    end
  end
end
