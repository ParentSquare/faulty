# frozen_string_literal: true

class Faulty
  module Storage
    # An prioritized list of storage backends
    #
    # If any backend fails, the next will be tried until one succeeds. This
    # should typically be used when using a fault-prone backend such as
    # {Storage::Redis}.
    #
    # This is used by {Faulty#initialize} if the `storage` option is set to an
    # array.
    #
    # @example
    #   # This storage will try Redis first, then fallback to memory storage
    #   # if Redis is unavailable.
    #   storage = Faulty::Storage::FallbackChain.new([
    #     Faulty::Storage::Redis.new,
    #     Faulty::Storage::Memory.new
    #   ])
    class FallbackChain
      attr_reader :options

      # Options for {FallbackChain}
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

      # Create a new {FallbackChain} to automatically fallback to reliable storage
      #
      # @param storages [Array<Storage::Interface>] An array of storage backends.
      #   The primary storage should be specified first. If that one fails,
      #   additional entries will be tried in sequence until one succeeds.
      # @param options [Hash] Attributes for {Options}
      # @yield [Options] For setting options in a block
      def initialize(storages, **options, &block)
        @storages = storages
        @options = Options.new(options, &block)
      end

      # Get options from the first available storage backend
      #
      # @param (see Interface#get_options)
      # @return (see Interface#get_options)
      def get_options(circuit)
        send_chain(:get_options, circuit) do |e|
          options.notifier.notify(:storage_failure, circuit: circuit, action: :get_options, error: e)
        end
      end

      # Try to set circuit options on all backends
      #
      # @param (see Interface#set_options)
      # @return (see Interface#set_options)
      def set_options(circuit, stored_options)
        send_all(:set_options, circuit, stored_options)
      end

      # Create a circuit entry in the first available storage backend
      #
      # @param (see Interface#entry)
      # @return (see Interface#entry)
      def entry(circuit, time, success, status)
        send_chain(:entry, circuit, time, success, status) do |e|
          options.notifier.notify(:storage_failure, circuit: circuit, action: :entry, error: e)
        end
      end

      # Open a circuit in the first available storage backend
      #
      # @param (see Interface#open)
      # @return (see Interface#open)
      def open(circuit, opened_at)
        send_chain(:open, circuit, opened_at) do |e|
          options.notifier.notify(:storage_failure, circuit: circuit, action: :open, error: e)
        end
      end

      # Reopen a circuit in the first available storage backend
      #
      # @param (see Interface#reopen)
      # @return (see Interface#reopen)
      def reopen(circuit, opened_at, previous_opened_at)
        send_chain(:reopen, circuit, opened_at, previous_opened_at) do |e|
          options.notifier.notify(:storage_failure, circuit: circuit, action: :reopen, error: e)
        end
      end

      # Close a circuit in the first available storage backend
      #
      # @param (see Interface#close)
      # @return (see Interface#close)
      def close(circuit)
        send_chain(:close, circuit) do |e|
          options.notifier.notify(:storage_failure, circuit: circuit, action: :close, error: e)
        end
      end

      # Lock a circuit in all storage backends
      #
      # @param (see Interface#lock)
      # @return (see Interface#lock)
      def lock(circuit, state)
        send_all(:lock, circuit, state)
      end

      # Unlock a circuit in all storage backends
      #
      # @param (see Interface#unlock)
      # @return (see Interface#unlock)
      def unlock(circuit)
        send_all(:unlock, circuit)
      end

      # Reset a circuit in all storage backends
      #
      # @param (see Interface#reset)
      # @return (see Interface#reset)
      def reset(circuit)
        send_all(:reset, circuit)
      end

      # Get the status of a circuit from the first available storage backend
      #
      # @param (see Interface#status)
      # @return (see Interface#status)
      def status(circuit)
        send_chain(:status, circuit) do |e|
          options.notifier.notify(:storage_failure, circuit: circuit, action: :status, error: e)
        end
      end

      # Get the history of a circuit from the first available storage backend
      #
      # @param (see Interface#history)
      # @return (see Interface#history)
      def history(circuit)
        send_chain(:history, circuit) do |e|
          options.notifier.notify(:storage_failure, circuit: circuit, action: :history, error: e)
        end
      end

      # Get the list of circuits from the first available storage backend
      #
      # @param (see Interface#list)
      # @return (see Interface#list)
      def list
        send_chain(:list) do |e|
          options.notifier.notify(:storage_failure, action: :list, error: e)
        end
      end

      # This is fault tolerant if any of the available backends are fault tolerant
      #
      # @param (see Interface#fault_tolerant?)
      # @return (see Interface#fault_tolerant?)
      def fault_tolerant?
        @storages.any?(&:fault_tolerant?)
      end

      private

      # Call a method on the backend and return the first successful result
      #
      # Short-circuits, so that if a call succeeds, no additional backends are
      # called.
      #
      # @param method [Symbol] The method to call
      # @param args [Array] The arguments to send
      # @raise [AllFailedError] AllFailedError if all backends fail
      # @return The return value from the first successful call
      def send_chain(method, *args)
        errors = []
        @storages.each do |s|
          begin
            return s.public_send(method, *args)
          rescue StandardError => e
            errors << e
            yield e
          end
        end

        raise AllFailedError.new("#{self.class}##{method} failed for all storage backends", errors)
      end

      # Call a method on every backend
      #
      # @param method [Symbol] The method to call
      # @param args [Array] The arguments to send
      # @raise [AllFailedError] AllFailedError if all backends fail
      # @raise [PartialFailureError] PartialFailureError if some but not all
      #   backends fail
      # @return [nil]
      def send_all(method, *args)
        errors = []
        @storages.each do |s|
          begin
            s.public_send(method, *args)
          rescue StandardError => e
            errors << e
          end
        end

        if errors.empty?
          nil
        elsif errors.size < @storages.size
          raise PartialFailureError.new("#{self.class}##{method} failed for some storage backends", errors)
        else
          raise AllFailedError.new("#{self.class}##{method} failed for all storage backends", errors)
        end
      end
    end
  end
end
