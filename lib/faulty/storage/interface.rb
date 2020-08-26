# frozen_string_literal: true

module Faulty
  module Storage
    # The interface required for a storage backend implementation
    #
    # This is for documentation only and is not loaded
    class Interface
      # Add a circuit run entry to storage
      #
      # The backend may choose to store this in whatever manner it chooses as
      # long as it can implement the other read methods.
      #
      # @param circuit [Circuit] The circuit that ran
      # @param time [Integer] The unix timestamp for the run
      # @param success [Boolean] True if the run succeeded
      # @return [Status] The circuit status after the run is added
      def entry(circuit, time, success)
        raise NotImplementedError
      end

      # Set the circuit state to open
      #
      # If multiple parallel processes open the circuit simultaneously, open
      # may be called more than once. If so, this method should return true
      # only once, when the circuit transitions from closed to open.
      #
      # If the backend does not support locking or atomic operations, then
      # it may always return true, but that could result in duplicate open
      # notifications.
      #
      # If returning true, this method also updates opened_at to the
      # current time.
      #
      # @param circuit [Circuit] The circuit to open
      # @param opened_at [Integer] The timestmp the circuit was opened at
      # @return [Boolean] True if the circuit transitioned from closed to open
      def open(circuit, opened_at)
        raise NotImplementedError
      end

      # Reset the opened_at time for a half_open circuit
      #
      # If multiple parallel processes open the circuit simultaneously, reopen
      # may be called more than once. If so, this method should return true
      # only once, when the circuit updates the opened_at value. It can use the
      # value from previous_opened_at to do a compare-and-set operation.
      #
      # If the backend does not support locking or atomic operations, then
      # it may always return true, but that could result in duplicate reopen
      # notifications.
      #
      # @param circuit [Circuit] The circuit to reopen
      # @param opened_at [Integer] The timestmp the circuit was opened at
      # @param previous_opened_at [Integer] The last known value of opened_at.
      #   Can be used to comare-and-set.
      # @return [Boolean] True if the opened_at time was updated
      def reopen(circuit, opened_at, previous_opened_at)
        raise NotImplementedError
      end

      # Set the circuit state to closed
      #
      # If multiple parallel processes close the circuit simultaneously, close
      # may be called more than once. If so, this method should return true
      # only once, when the circuit transitions from open to closed.
      #
      # If the backend does not support locking or atomic operations, then
      # it may always return true, but that could result in duplicate close
      # notifications.
      #
      # @return [Boolean] True if the circuit transitioned from open to closed
      def close(circuit)
        raise NotImplementedError
      end

      # Lock the circuit in a given state
      #
      # No concurrency gurantees are provided for locking
      #
      # @param circuit [Circuit] The circuit to lock
      # @param state [:open, :closed] The state to lock the circuit in
      # @return [void]
      def lock(circuit, state)
        raise NotImplementedError
      end

      # Unlock the circuit from any state
      #
      # No concurrency gurantees are provided for locking
      #
      # @param circuit [Circuit] The circuit to unlock
      # @return [void]
      def unlock(circuit)
        raise NotImplementedError
      end

      # Reset the circuit to a fresh state
      #
      # Clears all circuit status including entries, state, locks,
      # opened_at, and any other values that would affect Status.
      #
      # No concurrency gurantees are provided for resetting
      #
      # @param circuit [Circuit] The circuit to unlock
      # @return [void]
      def reset(circuit)
        raise NotImplementedError
      end

      # Get the status object for a circuit
      #
      # No concurrency gurantees are provided for getting status. It's possible
      # that status may represent a circuit in the middle of modification.
      #
      # @param circuit [Circuit] The circuit to get status for
      # @return [Status] The current status
      def status(circuit)
        raise NotImplementedError
      end

      # Get the entry history of a circuit
      #
      # No concurrency gurantees are provided for getting status. It's possible
      # that status may represent a circuit in the middle of modification.
      #
      # A storage backend may choose not to implement this method and instead
      # return an empty array.
      #
      # Each item in the history array is an array of two items (a tuple) of
      # `[run_time, succeeded]`, where `run_time` is a unix timestamp, and
      # `succeeded` is a boolean, true if the run succeeded.
      #
      # @param circuit [Circuit] The circuit to get history for
      # @return [Array<Array>] An array of history tuples
      def history(circuit)
        raise NotImplementedError
      end

      # Can this storage backend raise an error?
      #
      # If the storage backend returns false from this method, it will be wrapped
      # in a {FaultTolerantProxy}, otherwise it will be used as-is.
      #
      # @return [Boolean] True if this cache backend is fault tolerant
      def fault_tolerant?
        raise NotImplementedError
      end
    end
  end
end
