# frozen_string_literal: true

class Faulty
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
  # inside the circuit run block.
  class Circuit
    CACHE_REFRESH_SUFFIX = '.faulty_refresh'

    attr_reader :name

    # Options for {Circuit}
    #
    # @!attribute [r] cache_expires_in
    #   @return [Integer, nil] The number of seconds to keep
    #     cached results. A value of nil will keep the cache indefinitely.
    #     Default `86400`.
    # @!attribute [r] cache_refreshes_after
    #   @return [Integer, nil] The number of seconds after which we attempt
    #     to refresh the cache even if it's not expired. If the circuit fails,
    #     we continue serving the value from cache until `cache_expires_in`.
    #     A value of `nil` disables cache refreshing.
    #     Default `900`.
    # @!attribute [r] cache_refresh_jitter
    #   @return [Integer] The maximum number of seconds to randomly add or
    #     subtract from `cache_refreshes_after` when determining whether to
    #     refresh the cache.  A non-zero value helps reduce a "thundering herd"
    #     cache refresh in most scenarios. Set to `0` to disable jitter.
    #     Default `0.2 * cache_refreshes_after`.
    # @!attribute [r] cool_down
    #   @return [Integer] The number of seconds the circuit will
    #     stay open after it is tripped. Default 300.
    # @!attribute [r] error_mapper
    #   @return [Module, #call] Used by patches to set the namespace module for
    #     the faulty errors that will be raised. Should be a module or a callable.
    #     If given a module, the circuit assumes the module has error classes
    #     in that module. If given an object that responds to `#call` (a proc
    #     or lambda), the return value of the callable will be used. The callable
    #     is called with (`error_name`, `cause_error`, `circuit`). Default `Faulty`
    # @!attribute [r] evaluation_window
    #   @return [Integer] The number of seconds of history that
    #     will be evaluated to determine the failure rate for a circuit.
    #     Default `60`.
    # @!attribute [r] rate_threshold
    #   @return [Float] The minimum failure rate required to trip
    #     the circuit. For example, `0.5` requires at least a 50% failure rate to
    #     trip. Default `0.5`.
    # @!attribute [r] sample_threshold
    #   @return [Integer] The minimum number of runs required before
    #     a circuit can trip. A value of 1 means that the circuit will trip
    #     immediately when a failure occurs. Default `3`.
    # @!attribute [r] errors
    #   @return [Error, Array<Error>] An array of errors that are considered circuit
    #     failures. Default `[StandardError]`.
    # @!attribute [r] exclude
    #   @return [Error, Array<Error>] An array of errors that will not be
    #     captured by Faulty. These errors will not be considered circuit
    #     failures. Default `[]`.
    # @!attribute [r] cache
    #   @return [Cache::Interface] The cache backend. Default
    #   `Cache::Null.new`. Unlike {Faulty#initialize}, this is not wrapped in
    #   {Cache::AutoWire} by default.
    # @!attribute [r] notifier
    #   @return [Events::Notifier] A Faulty notifier. Default `Events::Notifier.new`
    # @!attribute [r] storage
    #   @return [Storage::Interface] The storage backend. Default
    #   `Storage::Memory.new`. Unlike {Faulty#initialize}, this is not wrapped
    #    in {Storage::AutoWire} by default.
    # @!attribute [r] registry
    #   @return [CircuitRegistry] For use by {Faulty} instances to facilitate
    #   memoization of circuits.
    Options = Struct.new(
      :cache_expires_in,
      :cache_refreshes_after,
      :cache_refresh_jitter,
      :cool_down,
      :evaluation_window,
      :rate_threshold,
      :sample_threshold,
      :errors,
      :error_mapper,
      :exclude,
      :cache,
      :notifier,
      :storage,
      :registry
    ) do
      include ImmutableOptions

      # Get the options stored in the storage backend
      #
      # @return [Hash] A hash of stored options
      def for_storage
        {
          cool_down: cool_down,
          evaluation_window: evaluation_window,
          rate_threshold: rate_threshold,
          sample_threshold: sample_threshold
        }
      end

      def defaults
        {
          cache_expires_in: 86_400,
          cache_refreshes_after: 900,
          cool_down: 300,
          errors: [StandardError],
          error_mapper: Faulty,
          exclude: [],
          evaluation_window: 60,
          rate_threshold: 0.5,
          sample_threshold: 3
        }
      end

      def required
        %i[
          cache
          cool_down
          errors
          error_mapper
          exclude
          evaluation_window
          rate_threshold
          sample_threshold
          notifier
          storage
        ]
      end

      def finalize
        self.cache ||= Cache::Default.new
        self.notifier ||= Events::Notifier.new
        self.storage ||= Storage::Memory.new
        self.errors = [errors] if errors && !errors.is_a?(Array)
        self.exclude = [exclude] if exclude && !exclude.is_a?(Array)

        unless cache_refreshes_after.nil?
          self.cache_refresh_jitter = 0.2 * cache_refreshes_after
        end
      end
    end

    # @return [String] Text representation of the circuit
    def inspect
      interested_opts = %i[
        cache_expires_in
        cache_refreshes_after
        cache_refresh_jitter
        cool_down evaluation_window
        rate_threshold
        sample_threshold
        errors exclude
      ]
      options_text = options.each_pair.map { |k, v| "#{k}: #{v}" if interested_opts.include?(k) }.compact.join(', ')
      %(#<#{self.class.name} name: #{name}, state: #{status.state}, options: { #{options_text} }>)
    end

    # @param name [String] The name of the circuit
    # @param options [Hash] Attributes for {Options}
    # @yield [Options] For setting options in a block
    def initialize(name, **options, &block)
      raise ArgumentError, 'name must be a String' unless name.is_a?(String)

      @name = name
      @given_options = Options.new(options, &block)
      @pulled_options = nil
      @options_pushed = false
    end

    # Get the options for this circuit
    #
    # If this circuit has been run, these will the options exactly as given
    # to {.new}. However, if this circuit has not yet been run, these options
    # will be supplemented by the last-known options from the circuit storage.
    #
    # Once a circuit is run, the given options are pushed to circuit storage to
    # be persisted.
    #
    # This is to allow circuit objects to behave as expected in contexts where
    # the exact options for a circuit are not known such as an admin dashboard
    # or in a debug console.
    #
    # Note that this distinction isn't usually important unless using
    # distributed circuit storage like the Redis storage backend.
    #
    # @example
    #   Faulty.circuit('api', cool_down: 5).run { api.users }
    #   # This status will be calculated using the cool_down of 5 because
    #   # the circuit was already run
    #   Faulty.circuit('api').status
    #
    # @example
    #   # This status will be calculated using the cool_down in circuit storage
    #   # if it is available instead of using the default value.
    #   Faulty.circuit('api').status
    #
    # @example
    #   # For typical usage, this behaves as expected, but note that it's
    #   # possible to run into some unexpected behavior when creating circuits
    #   # in unusual ways.
    #
    #   # For example, this status will be calculated using the cool_down in
    #   # circuit storage if it is available despite the given value of 5.
    #   Faulty.circuit('api', cool_down: 5).status
    #   Faulty.circuit('api').run { api.users }
    #   # However now, after the circuit is run, status will be calculated
    #   # using the given cool_down of 5 and the value of 5 will be pushed
    #   # permanently to circuit storage
    #   Faulty.circuit('api').status
    #
    # @return [Options] The resolved options
    def options
      return @given_options if @options_pushed
      return @pulled_options if @pulled_options

      stored = @given_options.storage.get_options(self)
      @pulled_options = stored ? @given_options.dup_with(stored) : @given_options
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
    def try_run(**options, &block)
      Result.new(ok: run(**options, &block))
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
    # When this is run, the given options are persisted to the storage backend.
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
    def run(cache: nil, &block)
      push_options
      cached_value = cache_read(cache)
      # return cached unless cached.nil?
      return cached_value if !cached_value.nil? && !cache_should_refresh?(cache)

      current_status = status
      return run_skipped(cached_value) unless current_status.can_run?

      run_exec(current_status, cached_value, cache, &block)
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
      @options_pushed = false
      @pulled_options = nil
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

    # Push the given options to circuit storage and set those as the current
    # options
    #
    # @return [void]
    def push_options
      return if @options_pushed

      @pulled_options = nil
      @options_pushed = true
      resolved = options.registry&.resolve(self)
      if resolved
        # If another circuit instance was resolved, don't store these options
        # Instead, copy the options from that circuit as if we were given those
        @given_options = resolved.options
      else
        storage.set_options(self, @given_options.for_storage)
      end
    end

    # Process a skipped run
    #
    # @param cached_value The cached value if one is available
    # @return The result from cache if available
    def run_skipped(cached_value)
      skipped!
      raise map_error(:OpenCircuitError) if cached_value.nil?

      cached_value
    end

    # Execute a run
    #
    # @param cached_value The cached value if one is available
    # @param cache_key [String, nil] The cache key if one is given
    # @return The run result
    def run_exec(status, cached_value, cache_key)
      result = yield
      success!(status)
      cache_write(cache_key, result)
      result
    rescue *options.errors => e
      raise if options.exclude.any? { |ex| e.is_a?(ex) }

      opened = failure!(status, e)
      if cached_value.nil?
        if opened
          raise map_error(:CircuitTrippedError, e)
        else
          raise map_error(:CircuitFailureError, e)
        end
      else
        cached_value
      end
    end

    # @return [Boolean] True if the circuit transitioned to closed
    def success!(status)
      storage.entry(self, Faulty.current_time, true, nil)
      closed = close! if status.half_open?

      options.notifier.notify(:circuit_success, circuit: self)
      closed
    end

    # @return [Boolean] True if the circuit transitioned to open
    def failure!(status, error)
      status = storage.entry(self, Faulty.current_time, false, status)
      options.notifier.notify(:circuit_failure, circuit: self, status: status, error: error)

      if status.half_open?
        reopen!(error, status.opened_at)
      elsif status.fails_threshold?
        open!(error)
      else
        false
      end
    end

    def skipped!
      options.notifier.notify(:circuit_skipped, circuit: self)
    end

    # @return [Boolean] True if the circuit transitioned from closed to open
    def open!(error)
      opened = storage.open(self, Faulty.current_time)
      options.notifier.notify(:circuit_opened, circuit: self, error: error) if opened
      opened
    end

    # @return [Boolean] True if the circuit was reopened
    def reopen!(error, previous_opened_at)
      reopened = storage.reopen(self, Faulty.current_time, previous_opened_at)
      options.notifier.notify(:circuit_reopened, circuit: self, error: error) if reopened
      reopened
    end

    # @return [Boolean] True if the circuit transitioned from half-open to closed
    def close!
      closed = storage.close(self)
      options.notifier.notify(:circuit_closed, circuit: self) if closed
      closed
    end

    # Read from the cache if it is configured
    #
    # @param key The key to read from the cache
    # @return The cached value, or nil if not present
    def cache_read(key)
      return unless key

      result = options.cache.read(key.to_s)
      event = result.nil? ? :circuit_cache_miss : :circuit_cache_hit
      options.notifier.notify(event, circuit: self, key: key)
      result
    end

    # Write to the cache if it is configured
    #
    # @param key The key to read from the cache
    # @return [void]
    def cache_write(key, value)
      return unless key

      options.notifier.notify(:circuit_cache_write, circuit: self, key: key)
      options.cache.write(key.to_s, value, expires_in: options.cache_expires_in)

      unless options.cache_refreshes_after.nil?
        options.cache.write(cache_refresh_key(key.to_s), next_refresh_time, expires_in: options.cache_expires_in)
      end
    end

    # Check whether the cache should be refreshed
    #
    # Should be called only if cache is present
    #
    # @return [Boolean] true if the cache should be refreshed
    def cache_should_refresh?(key)
      time = options.cache.read(cache_refresh_key(key.to_s)).to_i
      time + (((rand * 2) - 1) * options.cache_refresh_jitter) < Faulty.current_time
    end

    # Get the next time to refresh the cache when writing to it
    #
    # @return [Integer] The timestamp to refresh at
    def next_refresh_time
      (Faulty.current_time + options.cache_refreshes_after).floor
    end

    # Get the corresponding cache refresh key for a given cache key
    #
    # We use this to force a cache entry to refresh before it has expired
    #
    # @return [String] The cache refresh key
    def cache_refresh_key(key)
      "#{key}#{CACHE_REFRESH_SUFFIX}"
    end

    # Get a random number from 0.0 to 1.0 for use with cache jitter
    #
    # @return [Float] A random number from 0.0 to 1.0
    def rand
      SecureRandom.random_number
    end

    # Alias to the storage engine from options
    #
    # Always returns the value from the given options
    #
    # @return [Storage::Interface]
    def storage
      return Faulty::Storage::Null.new if Faulty.disabled?

      @given_options.storage
    end

    def map_error(error_name, cause = nil)
      if options.error_mapper.respond_to?(:call)
        options.error_mapper.call(error_name, cause, self)
      else
        options.error_mapper.const_get(error_name).new(cause&.message, self)
      end
    end
  end
end
