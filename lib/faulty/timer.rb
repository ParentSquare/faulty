# frozen_string_literal:true

class Faulty
  # The timer that Faulty uses to track relative times of circuit internals
  class Timer
    # Construct a new timer and save the offset from real time
    def initialize
      @offset = Time.now.to_f - Concurrent.monotonic_time
    end

    # Get the current monotonic time
    #
    # This is the system monotonic timer (if available) plus
    # the relative offset fom realtime set when the timer was constructed.
    #
    # Since various systems could treat realtime and monotonic time differently,
    # in a distributed environment, this can possibly lead to drift between
    # different systems.
    #
    # @return [Float]
    def current
      @offset + Concurrent.monotonic_time
    end
  end
end
