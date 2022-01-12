# frozen_string_literal: true

class Faulty
  module Storage
    # The default in-memory storage for circuits
    #
    # This implementation is thread-safe and circuit state is shared across
    # threads. Since state is stored in-memory, this state is not shared across
    # processes, or persisted across application restarts.
    #
    # Circuit state and runs are stored in memory. Although runs have a maximum
    # size within a circuit, there is no limit on the number of circuits that
    # can be stored. This means the user should be careful about the number of
    # circuits that are created. To that end, it's a good idea to avoid
    # dynamically-named circuits with this backend.
    #
    # For a more robust distributed implementation, use the {Redis} storage
    # backend.
    #
    # This can be used as a reference implementation for storage backends that
    # store a list of circuit run entries.
    #
    # @todo Add a more sophsticated implmentation that can limit the number of
    #   circuits stored.
    class Memory
      attr_reader :options

      # Options for {Memory}
      #
      # @!attribute [r] max_sample_size
      #   @return [Integer] The number of cache run entries to keep in memory
      #     for each circuit. Default `100`.
      Options = Struct.new(:max_sample_size) do
        include ImmutableOptions

        def defaults
          { max_sample_size: 100 }
        end
      end

      # The internal object for storing a circuit
      #
      # @private
      MemoryCircuit = Struct.new(:state, :runs, :opened_at, :lock, :options) do
        def initialize
          self.state = Concurrent::Atom.new(:closed)
          self.runs = Concurrent::MVar.new([], dup_on_deref: true)
          self.opened_at = Concurrent::Atom.new(nil)
          self.lock = nil
        end

        # Create a status object from the current circuit state
        #
        # @param circuit_options [Circuit::Options] The circuit options object
        # @return [Status] The newly created status
        def status(circuit_options)
          status = nil
          runs.borrow do |locked_runs|
            status = Faulty::Status.from_entries(
              locked_runs,
              state: state.value,
              lock: lock,
              opened_at: opened_at.value,
              options: circuit_options
            )
          end

          status
        end
      end

      # @param options [Hash] Attributes for {Options}
      # @yield [Options] For setting options in a block
      def initialize(**options, &block)
        @circuits = Concurrent::Map.new
        @options = Options.new(options, &block)
      end

      # Get the options stored for circuit
      #
      # @see Interface#get_options
      # @param (see Interface#get_options)
      # @return (see Interface#get_options)
      def get_options(circuit)
        fetch(circuit).options
      end

      # Store the options for a circuit
      #
      # @see Interface#set_options
      # @param (see Interface#set_options)
      # @return (see Interface#set_options)
      def set_options(circuit, stored_options)
        fetch(circuit).options = stored_options
      end

      # Add an entry to storage
      #
      # @see Interface#entry
      # @param (see Interface#entry)
      # @return (see Interface#entry)
      def entry(circuit, time, success, status)
        memory = fetch(circuit)
        memory.runs.borrow do |runs|
          runs.push([time, success])
          runs.shift if runs.size > options.max_sample_size
        end

        Status.from_entries(memory.runs.value, **status.to_h) if status
      end

      # Mark a circuit as open
      #
      # @see Interface#open
      # @param (see Interface#open)
      # @return (see Interface#open)
      def open(circuit, opened_at)
        memory = fetch(circuit)
        opened = memory.state.compare_and_set(:closed, :open)
        memory.opened_at.reset(opened_at) if opened
        opened
      end

      # Mark a circuit as reopened
      #
      # @see Interface#reopen
      # @param (see Interface#reopen)
      # @return (see Interface#reopen)
      def reopen(circuit, opened_at, previous_opened_at)
        memory = fetch(circuit)
        memory.opened_at.compare_and_set(previous_opened_at, opened_at)
      end

      # Mark a circuit as closed
      #
      # @see Interface#close
      # @param (see Interface#close)
      # @return (see Interface#close)
      def close(circuit)
        memory = fetch(circuit)
        memory.runs.modify { |_old| [] }
        memory.state.compare_and_set(:open, :closed)
      end

      # Lock a circuit open or closed
      #
      # @see Interface#lock
      # @param (see Interface#lock)
      # @return (see Interface#lock)
      def lock(circuit, state)
        memory = fetch(circuit)
        memory.lock = state
      end

      # Unlock a circuit
      #
      # @see Interface#unlock
      # @param (see Interface#unlock)
      # @return (see Interface#unlock)
      def unlock(circuit)
        memory = fetch(circuit)
        memory.lock = nil
      end

      # Reset a circuit
      #
      # @see Interface#reset
      # @param (see Interface#reset)
      # @return (see Interface#reset)
      def reset(circuit)
        @circuits.delete(circuit.name)
      end

      # Get the status of a circuit
      #
      # @see Interface#status
      # @param (see Interface#status)
      # @return (see Interface#status)
      def status(circuit)
        fetch(circuit).status(circuit.options)
      end

      # Get the circuit history up to `max_sample_size`
      #
      # @see Interface#history
      # @param (see Interface#history)
      # @return (see Interface#history)
      def history(circuit)
        fetch(circuit).runs.value
      end

      # Get a list of circuit names
      #
      # @return [Array<String>] The circuit names
      def list
        @circuits.keys
      end

      # Memory storage is fault-tolerant by default
      #
      # @return [true]
      def fault_tolerant?
        true
      end

      private

      # Fetch circuit storage safely or create it if it doesn't exist
      #
      # @return [MemoryCircuit]
      def fetch(circuit)
        @circuits.compute_if_absent(circuit.name) { MemoryCircuit.new }
      end
    end
  end
end
