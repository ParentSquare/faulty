# frozen_string_literal: true

class Faulty
  # The status of a circuit
  #
  # Includes information like the state and locks. Also calculates
  # whether a circuit can be run, or if it has failed a threshold.
  #
  # @!attribute [r] state
  #   @return [:open, :closed] The stored circuit state. This is always open
  #     or closed. Half-open is calculated from the current time. For that
  #     reason, calling state directly should be avoided. Instead use the
  #     status methods {#open?}, {#closed?}, and {#half_open?}.
  #     Default `:closed`
  # @!attribute [r] lock
  #   @return [:open, :closed, nil] If the circuit is locked, the state that
  #     it is locked in. Default `nil`.
  # @!attribute [r] opened_at
  #   @return [Float, nil] If the circuit is open, the timestamp ({Faulty.current_time})
  #     that it was opened. This is not necessarily reset when the circuit
  #     is closed. Default `nil`.
  # @!attribute [r] reserved_at
  #   @return [Float, nil] If a half-open test run was reserved, the
  #     timestamp ({Faulty.current_time}) of that reservation. Cleared when
  #     the circuit is closed.
  #     Not reset by {Storage::Interface#reopen}; the value naturally expires
  #     via `cool_down`. Default `nil`.
  #
  #     Only meaningful when {#state} is `:open`. If a backend race or bug
  #     produces an inconsistent shape (`state == :closed` with a non-nil
  #     `reserved_at`), it is normalized to `nil` at construction.
  # @!attribute [r] failure_rate
  #   @return [Float] A number from 0 to 1 representing the percentage of
  #     failures for the circuit. For exmaple 0.5 represents a 50% failure rate.
  # @!attribute [r] sample_size
  #   @return [Integer] The number of samples used to calculate the failure rate.
  # @!attribute [r] options
  #   @return [Circuit::Options] The options for the circuit
  # @!attribute [r] stub
  #   @return [Boolean] True if this status is a stub and not calculated from
  #     the storage backend. Used by {Storage::FaultTolerantProxy} when
  #     returning the status for an offline storage backend. Default `false`.
  Status = Struct.new(
    :state,
    :lock,
    :opened_at,
    :reserved_at,
    :failure_rate,
    :sample_size,
    :options,
    :stub
  )

  class Status
    include ImmutableOptions

    # @return [Float] The point in time captured when this status was built.
    #   All predicates (`open?`, `half_open?`, `reserved?`) reason about
    #   this same instant so they are mutually consistent. Held as an
    #   instance variable rather than a struct field so it does not leak
    #   into `to_h`, `==`, or `members` — those should reflect persisted
    #   circuit state, not a transient predicate-consistency snapshot.
    attr_reader :current_time

    def initialize(hash, &)
      @current_time = hash[:current_time] || Faulty.current_time
      super(hash.except(:current_time), &)
    end

    # The allowed state values
    STATES = %i[
      open
      closed
    ].freeze

    # The allowed lock values
    LOCKS = %i[
      open
      closed
    ].freeze

    # Create a new `Status` from a list of circuit runs
    #
    # For storage backends that store entries, this automatically calculates
    # failure_rate and sample size.
    #
    # @param entries [Array<Array>] An array of entry tuples. See
    #   {Circuit#history} for details
    # @param hash [Hash] The status attributes minus failure_rate and
    #   sample_size
    # @return [Status]
    def self.from_entries(entries, **hash)
      current_time = Faulty.current_time
      window_start = current_time - hash[:options].evaluation_window
      size = entries.size
      i = 0
      failures = 0
      sample_size = 0

      # This is a hot loop, and while is slightly faster than each
      while i < size
        time, success = entries[i]
        i += 1
        next unless time > window_start

        sample_size += 1
        failures += 1 unless success
      end

      new(hash.merge(
        sample_size: sample_size,
        failure_rate: sample_size.zero? ? 0.0 : failures.to_f / sample_size,
        current_time: current_time
      ))
    end

    # Whether the circuit is open
    #
    # This is mutually exclusive with {#closed?} and {#half_open?}
    #
    # @return [Boolean] True if open
    def open?
      state == :open && opened_at + options.cool_down > current_time
    end

    # Whether the circuit is closed
    #
    # This is mutually exclusive with {#open?} and {#half_open?}
    #
    # @return [Boolean] True if closed
    def closed?
      state == :closed
    end

    # Whether the circuit is half-open
    #
    # This is mutually exclusive with {#open?} and {#closed?}
    #
    # @return [Boolean] True if half-open
    def half_open?
      state == :open && opened_at + options.cool_down <= current_time
    end

    # Whether the circuit is locked open
    #
    # @return [Boolean] True if locked open
    def locked_open?
      lock == :open
    end

    # Whether the circuit is locked closed
    #
    # @return [Boolean] True if locked closed
    def locked_closed?
      lock == :closed
    end

    # Whether a half-open test run is currently reserved
    #
    # Process-agnostic: returns true whenever an unexpired reservation exists
    # on this circuit, regardless of who made it. The "did someone else reserve
    # this?" interpretation only applies when this predicate is read on a
    # status snapshot taken *before* the caller attempts {Storage::Interface#reserve};
    # a caller introspecting their own status after a successful reserve will
    # also see `true` here.
    #
    # The reservation expires after `cool_down` to handle the case where the
    # process that made the reservation crashes before resolving the circuit.
    # Side effect: a legitimately-slow test run that exceeds `cool_down`
    # loses exclusivity (another process may reserve and run concurrently).
    # See the "How it Works" section of the README for the full trade-off.
    #
    # @return [Boolean] True if a reservation is in effect
    def reserved?
      return false unless reserved_at

      state == :open && reserved_at + options.cool_down > current_time
    end

    # Whether the circuit can be run
    #
    # Takes the circuit state, locks and cooldown into account. Locks are
    # operator overrides and take precedence over both state and reservation,
    # so a `locked_closed?` circuit always runs and a `locked_open?` circuit
    # never runs.
    #
    # @return [Boolean] True if the circuit can be run
    def can_run?
      return false if locked_open?
      return true if locked_closed?
      return false if reserved?

      closed? || half_open?
    end

    # Whether the circuit fails the sample size and rate thresholds
    #
    # @return [Boolean] True if the circuit fails the thresholds
    def fails_threshold?
      return false if sample_size < options.sample_threshold

      failure_rate >= options.rate_threshold
    end

    def finalize
      raise ArgumentError, "state must be a symbol in #{self.class}::STATES" unless STATES.include?(state)
      unless lock.nil? || LOCKS.include?(lock)
        raise ArgumentError, "lock must be a symbol in #{self.class}::LOCKS or nil"
      end
      raise ArgumentError, 'opened_at is required if state is open' if state == :open && opened_at.nil?

      # `reserved_at` is only meaningful while the circuit is open. Backends
      # are expected to clear it on close, but if a brief race or backend bug
      # leaves a stale value paired with `state == :closed`, normalize it
      # here so downstream code can rely on the invariant without checking
      # `state` first. Sanitizing rather than raising avoids turning a
      # transient backend inconsistency into a production crash.
      self.reserved_at = nil if state == :closed && !reserved_at.nil?
    end

    def required
      %i[state failure_rate sample_size options stub]
    end

    def defaults
      {
        state: :closed,
        failure_rate: 0.0,
        sample_size: 0,
        stub: false
      }
    end
  end
end
