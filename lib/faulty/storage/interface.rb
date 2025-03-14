# frozen_string_literal: true

class Faulty
  module Storage
    # The interface required for a storage backend implementation
    #
    # This is for documentation only and is not loaded
    class Interface
      # Get the options stored for circuit
      #
      # They should be returned exactly as given by {#set_options}
      #
      # @return [Hash] A hash of the options stored by {#set_options}. The keys
      #   must be symbols.
      def get_options(circuit)
        raise NotImplementedError
      end

      # Store the options for a circuit
      #
      # They should be returned exactly as given by {#set_options}
      #
      # @param circuit [Circuit] The circuit to set options for
      # @param stored_options [Hash<Symbol, Object>] A hash of symbol option names to
      #   circuit options. These option values are guranteed to be primive
      #   values.
      # @return [void]
      def set_options(circuit, stored_options)
        raise NotImplementedError
      end

      # Add a circuit run entry to storage
      #
      # The backend may choose to store this in whatever manner it chooses as
      # long as it can implement the other read methods.
      #
      # @param circuit [Circuit] The circuit that ran
      # @param time [Float] The unix timestamp for the run, from
      #   {Faulty.current_time}
      # @param success [Boolean] True if the run succeeded
      # @param status [Status, nil] The previous status. If given, this method must
      #   return an updated status object from the new entry data.
      # @return [Status, nil] If `status` is not nil, the updated status object.
      def entry(circuit, time, success, status)
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
      # @param opened_at [Float] The timestamp the circuit was opened at,
      #   from {Faulty.current_time}
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
      # The backend MUST NOT clear `reserved_at` here.
      #
      # Preserving the prior cycle's `reserved_at` is load-bearing for
      # half-open exclusivity. If a late-arriving caller read status while
      # `reserved_at` was still nil (before the winning process reserved),
      # its subsequent `reserve(circuit, T, nil)` CAS must fail. Clearing
      # `reserved_at` in `reopen` would let that stale CAS incorrectly
      # succeed and produce a duplicate half-open run.
      #
      # Beyond exclusivity, the prior reservation expires naturally at
      # `reserved_at + cool_down`, aligned with the start of the next
      # half-open window (since `reserved_at <= new_opened_at`). An
      # explicit reset would be redundant with the cool-down-aligned expiry
      # that already handles crash recovery.
      #
      # This invariant assumes the reservation TTL equals `cool_down`. If
      # a separate `reservation_ttl` is ever introduced, this method must
      # be revisited and may need to clear `reserved_at` explicitly.
      #
      # @param circuit [Circuit] The circuit to reopen
      # @param opened_at [Float] The timestamp the circuit was opened at,
      #   from {Faulty.current_time}
      # @param previous_opened_at [Float] The last known value of opened_at.
      #   Can be used to compare-and-set. Always non-nil — `Circuit#failure!`
      #   only enters the reopen branch when `status.half_open?` is true,
      #   which requires non-nil `opened_at`. Unlike `previous_reserved_at`
      #   on {#reserve}, there is no legitimate "no prior value" call path
      #   to `reopen`, so backends may treat this parameter as required and
      #   are not expected to handle `nil`.
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
      # The backend should reset the reserved_at value to empty when closing
      # the circuit.
      #
      # If the backend does not support locking or atomic operations, then
      # it may always return true, but that could result in duplicate close
      # notifications.
      #
      # @return [Boolean] True if the circuit transitioned from open to closed
      def close(circuit)
        raise NotImplementedError
      end

      # Reserve an exclusive run for this circuit
      #
      # This is used when the circuit is half-open and the test run is being
      # attempted. We need to make sure only a single run is allowed.
      #
      # The backend should store reserved_at and use it to serve future status
      # requests. When setting reserved_at, the backend should atomically
      # compare any existing value using previous_reserved_at. This ensures
      # that mutltiple parallel processes can't reserve the circuit.
      #
      # The return value is the caller's signal to proceed with the half-open
      # test run, not a strict report of whether atomic acquisition succeeded.
      # Atomic backends should return `true` only when the CAS against
      # `previous_reserved_at` succeeds. Non-atomic backends, no-op backends
      # ({Null}), or wrappers that fail open ({FaultTolerantProxy}) may always
      # return `true`; the caller will proceed at the cost of allowing
      # duplicate half-open test runs.
      #
      # @param circuit [Circuit] The circuit to reserve
      # @param reserved_at [Float] The timestamp of this reservation, from
      #   {Faulty.current_time}
      # @param previous_reserved_at [Float, nil] The last known value of
      #   reserved_at, or nil for the first reservation in a new open cycle.
      #   Can be used to compare-and-set.
      # @return [Boolean] True if the caller may proceed with the half-open
      #   test run; false if another caller already holds the reservation.
      def reserve(circuit, reserved_at, previous_reserved_at)
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
      # opened_at, options, and any other values that would affect Status.
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

      # Get a list of all circuit names
      #
      # If the storage backend does not support listing circuits, this may
      # return an empty array.
      #
      # @return [Array<String>]
      def list
        raise NotImplementedError
      end

      # Reset all circuits
      #
      # Some implementions may clear circuits on a best-effort basis since
      # all circuits may not be known.
      #
      # @raise NotImplementedError If the storage backend does not support clearing.
      # @return [void]
      def clear
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
