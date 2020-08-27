# frozen_string_literal: true

module Faulty
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
  #   @return [Integer, nil] If the circuit is open, the timestamp that it was
  #     opened. This is not necessarily reset when the circuit is closed.
  #     Default `nil`.
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
    :failure_rate,
    :sample_size,
    :options,
    :stub
  ) do
    include ImmutableOptions

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
      failures = 0
      sample_size = 0
      entries.each do |(time, success)|
        next unless time > Faulty.current_time - hash[:options].evaluation_window

        sample_size += 1
        failures += 1 unless success
      end

      new(hash.merge(
        sample_size: sample_size,
        failure_rate: sample_size.zero? ? 0.0 : failures.to_f / sample_size
      ))
    end

    # Whether the circuit is open
    #
    # This is mutually exclusive with {#closed?} and {#half_open?}
    #
    # @return [Boolean] True if open
    def open?
      state == :open && opened_at + options.cool_down > Faulty.current_time
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
      state == :open && opened_at + options.cool_down <= Faulty.current_time
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

    # Whether the circuit can be run
    #
    # Takes the circuit state, locks and cooldown into account
    #
    # @return [Boolean] True if the circuit can be run
    def can_run?
      return false if locked_open?

      closed? || locked_closed? || half_open?
    end

    # Whether the circuit fails the sample size and rate thresholds
    #
    # @return [Boolean] True if the circuit fails the thresholds
    def fails_threshold?
      return false if sample_size < options.sample_threshold

      failure_rate >= options.rate_threshold
    end

    private

    def finalize
      raise ArgumentError, "state must be a symbol in #{self.class}::STATES" unless STATES.include?(state)
      unless lock.nil? || LOCKS.include?(state)
        raise ArgumentError, "lock must be a symbol in #{self.class}::LOCKS or nil"
      end
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
