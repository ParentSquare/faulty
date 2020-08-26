# frozen_string_literal: true

module Faulty
  module Storage
    class Memory
      attr_reader :options

      Options = Struct.new(:max_sample_size) do
        include ImmutableOptions

        def defaults
          { max_sample_size: 100 }
        end
      end

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
