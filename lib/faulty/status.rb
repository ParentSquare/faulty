# frozen_string_literal: true

module Faulty
  Status = Struct.new(
    :state,
    :lock,
    :opened_at,
    :failure_rate,
    :sample_size,
    :cool_down,
    :sample_threshold,
    :rate_threshold,
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

    def open?
      state == :open && opened_at + cool_down > Faulty.current_time
    end

    def closed?
      state == :closed
    end

    def half_open?
      state == :open && opened_at + cool_down <= Faulty.current_time
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
      return false if sample_size < sample_threshold

      failure_rate >= rate_threshold
    end

    private

    def finalize
      raise ArgumentError, "state must be a symbol in #{self.class}::STATES" unless STATES.include?(state)
      unless lock.nil? || LOCKS.include?(state)
        raise ArgumentError, "lock must be a symbol in #{self.class}::LOCKS or nil"
      end
    end

    def required
      %i[state failure_rate sample_size cool_down sample_threshold rate_threshold stub]
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
