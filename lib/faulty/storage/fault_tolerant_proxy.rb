# frozen_string_literal: true

class Faulty
  module Storage
    # A wrapper for storage backends that may raise errors
    #
    # {Faulty#initialize} automatically wraps all non-fault-tolerant storage backends with
    # this class.
    #
    # If the storage backend raises a `StandardError`, it will be captured and
    # sent to the notifier.
    class FaultTolerantProxy
      extend Forwardable

      attr_reader :options

      # Options for {FaultTolerantProxy}
      #
      # @!attribute [r] notifier
      #   @return [Events::Notifier] A Faulty notifier
      Options = Struct.new(
        :notifier
      ) do
        include ImmutableOptions

        def required
          %i[notifier]
        end
      end

      # @param storage [Storage::Interface] The storage backend to wrap
      # @param options [Hash] Attributes for {Options}
      # @yield [Options] For setting options in a block
      def initialize(storage, **options, &block)
        @storage = storage
        @options = Options.new(options, &block)
      end

      # Wrap a storage backend in a FaultTolerantProxy unless it's already
      # fault tolerant
      #
      # @param storage [Storage::Interface] The storage to maybe wrap
      # @return [Storage::Interface] The original storage or a {FaultTolerantProxy}
      def self.wrap(storage, **options, &block)
        return storage if storage.fault_tolerant?

        new(storage, **options, &block)
      end

      # @!method lock(circuit, state)
      #   Lock is not called in normal operation, so it doesn't capture errors
      #
      #   @see Interface#lock
      #   @param (see Interface#lock)
      #   @return (see Interface#lock)
      #
      # @!method unlock(circuit)
      #   Unlock is not called in normal operation, so it doesn't capture errors
      #
      #   @see Interface#unlock
      #   @param (see Interface#unlock)
      #   @return (see Interface#unlock)
      #
      # @!method reset(circuit)
      #   Reset is not called in normal operation, so it doesn't capture errors
      #
      #   @see Interface#reset
      #   @param (see Interface#reset)
      #   @return (see Interface#reset)
      #
      # @!method history(circuit)
      #   History is not called in normal operation, so it doesn't capture errors
      #
      #   @see Interface#history
      #   @param (see Interface#history)
      #   @return (see Interface#history)
      #
      # @!method list
      #   List is not called in normal operation, so it doesn't capture errors
      #
      #   @see Interface#list
      #   @param (see Interface#list)
      #   @return (see Interface#list)
      def_delegators :@storage, :lock, :unlock, :reset, :history, :list

      # Get circuit options safely
      #
      # @see Interface#get_options
      # @param (see Interface#get_options)
      # @return (see Interface#get_options)
      def get_options(circuit)
        @storage.get_options(circuit)
      rescue StandardError => e
        options.notifier.notify(:storage_failure, circuit: circuit, action: :get_options, error: e)
        nil
      end

      # Set circuit options safely
      #
      # @see Interface#get_options
      # @param (see Interface#set_options)
      # @return (see Interface#set_options)
      def set_options(circuit, stored_options)
        @storage.set_options(circuit, stored_options)
      rescue StandardError => e
        options.notifier.notify(:storage_failure, circuit: circuit, action: :set_options, error: e)
        nil
      end

      # Add a history entry safely
      #
      # @see Interface#entry
      # @param (see Interface#entry)
      # @return (see Interface#entry)
      def entry(circuit, time, success, status)
        @storage.entry(circuit, time, success, status)
      rescue StandardError => e
        options.notifier.notify(:storage_failure, circuit: circuit, action: :entry, error: e)
        stub_status(circuit) if status
      end

      # Safely mark a circuit as open
      #
      # @see Interface#open
      # @param (see Interface#open)
      # @return (see Interface#open)
      def open(circuit, opened_at)
        @storage.open(circuit, opened_at)
      rescue StandardError => e
        options.notifier.notify(:storage_failure, circuit: circuit, action: :open, error: e)
        false
      end

      # Safely mark a circuit as reopened
      #
      # @see Interface#reopen
      # @param (see Interface#reopen)
      # @return (see Interface#reopen)
      def reopen(circuit, opened_at, previous_opened_at)
        @storage.reopen(circuit, opened_at, previous_opened_at)
      rescue StandardError => e
        options.notifier.notify(:storage_failure, circuit: circuit, action: :reopen, error: e)
        false
      end

      # Safely mark a circuit as closed
      #
      # @see Interface#close
      # @param (see Interface#close)
      # @return (see Interface#close)
      def close(circuit)
        @storage.close(circuit)
      rescue StandardError => e
        options.notifier.notify(:storage_failure, circuit: circuit, action: :close, error: e)
        false
      end

      # Safely get the status of a circuit
      #
      # If the backend is unavailable, this returns a stub status that
      # indicates that the circuit is closed.
      #
      # @see Interface#status
      # @param (see Interface#status)
      # @return (see Interface#status)
      def status(circuit)
        @storage.status(circuit)
      rescue StandardError => e
        options.notifier.notify(:storage_failure, circuit: circuit, action: :status, error: e)
        stub_status(circuit)
      end

      # This cache makes any storage fault tolerant, so this is always `true`
      #
      # @return [true]
      def fault_tolerant?
        true
      end

      private

      # Create a stub status object to close the circuit by default
      #
      # @return [Status] The stub status
      def stub_status(circuit)
        Faulty::Status.new(
          options: circuit.options,
          stub: true
        )
      end
    end
  end
end
