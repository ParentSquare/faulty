# frozen_string_literal: true

module Faulty
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

    STATES = %i[
      open
      closed
    ].freeze

    LOCKS = %i[
      open
      closed
    ].freeze

    def self.from_entries(entries, **attrs)
      failures = 0
      sample_size = 0
      entries.each do |(time, success)|
        next unless time > Faulty.current_time - attrs[:options].evaluation_window

        sample_size += 1
        failures += 1 unless success
      end

      new(attrs.merge(
        sample_size: sample_size,
        failure_rate: sample_size.zero? ? 0.0 : failures.to_f / sample_size
      ))
    end

    def open?
      state == :open && opened_at + options.cool_down > Faulty.current_time
    end

    def closed?
      state == :closed
    end

    def half_open?
      state == :open && opened_at + options.cool_down <= Faulty.current_time
    end

    def locked_open?
      lock == :open
    end

    def locked_closed?
      lock == :closed
    end

    def can_run?
      return false if locked_open?

      closed? || locked_closed? || half_open?
    end

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
