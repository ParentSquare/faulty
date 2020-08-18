# frozen_string_literal: true

module Faulty
  # Runs code protected by a circuit breaker
  #
  # https://www.martinfowler.com/bliki/CircuitBreaker.html
  #
  # A circuit is intended to protect against repeated calls to a failing
  # external dependency. For example, a vendor API may be failing continuously.
  # In that case, we trip the circuit breaker and stop calling that API for
  # a specified cool-down period.
  #
  # Once the cool-down passes, we try the API again, and if it succeeds, we reset
  # the circuit.
  #
  # Why isn't there a timeout option?
  # -----------------
  # Timeout is inherently unsafe, and
  # should not be used blindly.
  # See [Why Ruby's timeout is Dangerous](https://jvns.ca/blog/2015/11/27/why-rubys-timeout-is-dangerous-and-thread-dot-raise-is-terrifying).
  #
  # You should prefer a network timeout like `open_timeout` and `read_timeout`, or
  # write your own code to periodically check how long it has been running.
  # If you're sure you want ruby's generic Timeout, you can apply it yourself
  # inside the circuit block.
  class Circuit # rubocop:disable Metrics/ClassLength
    attr_reader :name
    attr_reader :options

    # @!attribute [r] cache_expires_in
    #   @return [Integer, nil] The number of seconds to keep
    #     cached results. A value of nil will keep the cache indefinitely.
    #     Default `900`.
    # @!attribute [r] cool_down
    #   @return [Integer] The number of seconds the circuit will
    #     stay open after it is tripped. Default 300.
    # @!attribute [r] evaluation_window
    #   @return [Integer] The number of seconds of history that
    #     will be evaluated to determine the failure rate for a circuit.
    #     Default `60`.
    # @!attribute [r] rate_threshold
    #   @return [Float] The minimum failure rate required to trip
    #     the circuit. For example, `0.5` requires at least a 50% failure rate to
    #     trip. Default `0.5`.
    # @!attribute [r] rate_min_sample
    #   @return [Integer] The minimum number of runs required before
    #     a circuit can trip. A value of 1 means that the circuit will trip
    #     immediately when a failure occurs. Default `3`.
    # @!attribute [r] errors
    #   @return [Array<Error>] An array of errors that are considered circuit
    #     failures. Default `[StandardError]`.
    # @!attribute [r] exclude
    #   @return [Array<Error>] An array of errors that will be captured and
    #     considered circuit failures. Default `[]`.
    # @!attribute [r] cache
    #   @return [Cache::Interface] The cache backend if cache support is desired.
    # @!attribute [r] notifier
    #   @return [Events::Notifier] A Faulty notifier
    # @!attribute [r] storage
    #   @return [Storage::Interface] The storage backend
    Options = Struct.new(
      :cache_expires_in,
      :cool_down,
      :evaluation_window,
      :rate_threshold,
      :rate_min_sample,
      :errors,
      :exclude,
      :cache,
      :notifier,
      :storage
    ) do
      include ImmutableOptions

      private

      def defaults
        {
          cache_expires_in: 900,
          cool_down: 300,
          errors: [StandardError],
          exclude: [],
          evaluation_window: 60,
          rate_threshold: 0.5,
          rate_min_sample: 3
        }
      end

      def required
        %i[
          cache_expires_in
          cool_down
          errors
          exclude
          evaluation_window
          rate_threshold
          rate_min_sample
          notifier
          storage
        ]
      end
    end

    # @param name [Symbol, String] The name of the circuit
    # @param options [Hash] Attributes for {Options}
    # @yield [Options] For setting options in a block
    def initialize(name, **options, &block)
      @name = name
      @options = Options.new(options, &block)
    end

    # Run the circuit as with {#run}, but return a {Result}
    #
    # This is syntax sugar for running a circuit and rescuing an error
    #
    # @example
    #   result = Faulty.circuit(:api).try_run do
    #     api.get
    #   end
    #
    #   response = if result.ok?
    #     result.get
    #   else
    #     { error: result.error.message }
    #   end
    #
    # @example
    #   # The Result object has a fetch method that can return a default value
    #   # if an error occurs
    #   result = Faulty.circuit(:api).try_run do
    #     api.get
    #   end.fetch({})
    #
    # @param (see #run)
    # @yield (see #run)
    # @raise If the block raises an error not in the error list, or if the error
    #   is excluded.
    # @return [Result<Object, Error>] A result where the ok value is the return
    #   value of the block, or the error value is an error captured by the
    #   circuit.
    def try_run(**options)
      Result.new(ok: run(**options, &Proc.new))
    rescue FaultyError => e
      Result.new(error: e)
    end

    # Run a block protected by this circuit
    #
    # If the circuit is closed, the block will run. Any exceptions raised inside
    # the block will be checked against the error and exclude options to determine
    # whether that error should be captured. If the error is captured, this
    # run will be recorded as a failure.
    #
    # If the circuit exceeds the failure conditions, this circuit will be tripped
    # and marked as open. Any future calls to run will not execute the block, but
    # instead wait for the cool down period. Once the cool down period passes,
    # the circuit transitions to half-open, and the block will be allowed to run.
    #
    # If the circuit fails again while half-open, the circuit will be closed for
    # a second cool down period. However, if the circuit completes successfully,
    # the circuit will be closed and reset to its initial state.
    #
    # @param cache [String, nil] A cache key, or nil if caching is not desired
    # @yield The block to protect with this circuit
    # @raise If the block raises an error not in the error list, or if the error
    #   is excluded.
    # @raise {OpenCircuitError} if the circuit is open
    # @raise {CircuitTrippedError} if this run causes the circuit to trip. It's
    #   possible for concurrent runs to simultaneously trip the circuit if the
    #   storage engine is not concurrency-safe.
    # @raise {CircuitFailureError} if this run fails, but doesn't cause the
    #   circuit to trip
    # @return The return value of the block
    def run(cache: nil)
      result = cache_read(cache)
      return result unless result.nil?

      unless status.can_run?
        skipped!
        raise OpenCircuitError.new(nil, self)
      end

      begin
        result = yield
        success!
        cache_write(cache, result)
        result
      rescue *options.errors => e
        raise if options.exclude.any? { |ex| e.is_a?(ex) }

        raise CircuitTrippedError.new(nil, self) if failure!(e)

        raise CircuitFailureError.new(nil, self)
      end
    end

    # Force the circuit to stay open until unlocked
    #
    # @return [self]
    def lock_open!
      storage.lock(self, :open)
      self
    end

    # Force the circuit to stay closed until unlocked
    #
    # @return [self]
    def lock_closed!
      storage.lock(self, :closed)
      self
    end

    # Remove any open or closed locks
    #
    # @return [self]
    def unlock!
      storage.unlock(self)
      self
    end

    # Reset this circuit to its initial state
    #
    # This removes the current state, all history, and locks
    #
    # @return [self]
    def reset!
      storage.reset(self)
      self
    end

    # Get the current status of the circuit
    #
    # This method is not safe for concurrent operations, so it's unsafe
    # to check this method and make runtime decisions based on that. However,
    # it's useful for getting a non-synchronized snapshot of a circuit.
    #
    # @return [Status]
    def status
      storage.status(self)
    end

    # Get the history of runs of this circuit
    #
    # The history is an array of tuples where the first value is
    # the run time, and the second value is a boolean which is true
    # if the run was successful.
    #
    # @return [Array<Array>>] An array of tuples of [run_time, is_success]
    def history
      storage.history(self)
    end

    private

    # @return [Boolean] True if the circuit transitioned to closed
    def success!
      status = storage.entry(self, Faulty.current_time, true)
      closed = false
      closed = close! if should_close?(status)

      options.notifier.notify(:circuit_success, circuit: self, status: status)
      closed
    end

    # @return [Boolean] True if the circuit transitioned to open
    def failure!(error)
      status = storage.entry(self, Faulty.current_time, false)
      options.notifier.notify(:circuit_failure, circuit: self, status: status, error: error)

      opened = false
      opened = open!(error) if should_open?(status)

      opened
    end

    def skipped!
      options.notifier.notify(:circuit_skipped, circuit: self)
    end

    # @return [Boolean] True if the circuit transitioned from closed to open
    def open!(error)
      opened = storage.open(self)
      options.notifier.notify(:circuit_opened, circuit: self, error: error) if opened
      opened
    end

    # @return [Boolean] True if the circuit transitioned from half-open to closed
    def close!
      closed = storage.close(self)
      options.notifier.notify(:circuit_closed, circuit: self) if closed
      closed
    end

    # Test whether we should open the circuit after a failed run
    #
    # @return [Boolean] True if we should open the circuit from closed
    def should_open?(status)
      return true if status.half_open?
      return true if status.fails_threshold?

      false
    end

    # Test whether we should close after a successful run
    #
    # Currently this is always true if the circuit is half-open, which is the
    # traditional behavior for a circuit-breaker
    #
    # @return [Boolean] True if we should close the circuit from half-open
    def should_close?(status)
      status.half_open?
    end

    # Read from the cache if it is configured
    #
    # @param key The key to read from the cache
    # @return The cached value, or nil if not present
    def cache_read(key)
      return unless key
      return unless options.cache

      options.cache.read(key.to_s)
    end

    # Write to the cache if it is configured
    #
    # @param key The key to read from the cache
    # @return [void]
    def cache_write(key, value)
      return unless key
      return unless options.cache

      options.cache.write(key.to_s, value, expires_in: options.cache_expires_in)
    end

    # Alias to the storage engine from options
    #
    # @return [Storage::Interface]
    def storage
      options.storage
    end
  end
end
