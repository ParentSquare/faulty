# frozen_string_literal: true

module Faulty
  module Storage
    # The default in-memory storage for circuits
    #
    # This implementation is most suitable to single-process, low volume
    # usage. It is thread-safe and circuit state is shared across threads.
    #
    # Circuit state and runs are stored in memory. Although runs have a maximum
    # size within a circuit, there is no limit on the number of circuits that
    # can be stored. This means the user should be careful about the number of
    # circuits that are created. To that end, it's a good idea to avoid
    # dynamically-named circuits with this backend.
    #
    # For a more robust multi-process implementation, use the {Redis} storage
    # backend.
    #
    # This can be used as a reference implementation for storage backends that
    # store a list of circuit run entries.
    class Memory
      attr_reader :options

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
      MemoryCircuit = Struct.new(:state, :runs, :opened_at, :lock) do
        def initialize
          self.state = Concurrent::Atom.new(:closed)
          self.runs = Concurrent::MVar.new([], dup_on_deref: true)
          self.opened_at = Concurrent::Atom.new(nil)
          self.lock = nil
        end

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

      # @return [Status]
      def entry(circuit, time, success)
        memory = fetch(circuit)
        memory.runs.borrow do |runs|
          runs.push([time, success])
          runs.pop if runs.size > options.max_sample_size
        end
        memory.status(circuit.options)
      end

      # @return [Boolean] True if the circuit transitioned from closed to open
      def open(circuit, opened_at)
        memory = fetch(circuit)
        opened = memory.state.compare_and_set(:closed, :open)
        memory.opened_at.reset(opened_at) if opened
        opened
      end

      # @return [void]
      def reopen(circuit, opened_at, previous_opened_at)
        memory = fetch(circuit)
        memory.opened_at.compare_and_set(previous_opened_at, opened_at)
      end

      # @return [Boolean] True if the circuit transitioned from open to closed
      def close(circuit)
        memory = fetch(circuit)
        memory.runs.modify { |_old| [] }
        memory.state.compare_and_set(:open, :closed)
      end

      def lock(circuit, state)
        memory = fetch(circuit)
        memory.lock = state
      end

      def unlock(circuit)
        memory = fetch(circuit)
        memory.lock = nil
      end

      def reset(circuit)
        @circuits.delete(circuit.name)
      end

      def status(circuit)
        fetch(circuit).status(circuit.options)
      end

      def history(circuit)
        fetch(circuit).runs.value
      end

      def fault_tolerant?
        true
      end

      private

      def fetch(circuit)
        @circuits.compute_if_absent(circuit.name) { MemoryCircuit.new }
      end
    end
  end
end
