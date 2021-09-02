# frozen_string_literal: true

class Faulty
  module Storage
    # A no-op backend for disabling circuits
    class Null
      # Define a single global instance
      @instance = new

      def self.new
        @instance
      end

      # @param (see Interface#entry)
      # @return (see Interface#entry)
      def entry(_circuit, _time, _success)
        []
      end

      # @param (see Interface#open)
      # @return (see Interface#open)
      def open(_circuit, _opened_at)
        true
      end

      # @param (see Interface#reopen)
      # @return (see Interface#reopen)
      def reopen(_circuit, _opened_at, _previous_opened_at)
        true
      end

      # @param (see Interface#close)
      # @return (see Interface#close)
      def close(_circuit)
        true
      end

      # @param (see Interface#lock)
      # @return (see Interface#lock)
      def lock(_circuit, _state)
      end

      # @param (see Interface#unlock)
      # @return (see Interface#unlock)
      def unlock(_circuit)
      end

      # @param (see Interface#reset)
      # @return (see Interface#reset)
      def reset(_circuit)
      end

      # @param (see Interface#status)
      # @return (see Interface#status)
      def status(circuit)
        Faulty::Status.new(
          options: circuit.options,
          stub: true
        )
      end

      # @param (see Interface#history)
      # @return (see Interface#history)
      def history(_circuit)
        []
      end

      # @param (see Interface#list)
      # @return (see Interface#list)
      def list
        []
      end

      # This backend is fault tolerant
      #
      # @param (see Interface#fault_tolerant?)
      # @return (see Interface#fault_tolerant?)
      def fault_tolerant?
        true
      end
    end
  end
end
