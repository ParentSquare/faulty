# frozen_string_literal: true

class Faulty
  module Storage
    # A storage backend for storing circuit state in Redis.
    #
    # When using this or any networked backend, be sure to evaluate the risk,
    # and set conservative timeouts so that the circuit storage does not cause
    # cascading failures in your application when evaluating circuits. Always
    # wrap this backend with a {FaultTolerantProxy} to limit the effect of
    # these types of events.
    class Redis # rubocop:disable Metrics/ClassLength
      # Separates the time/status for history entry strings
      ENTRY_SEPARATOR = ':'

      attr_reader :options

      # Options for {Redis}
      #
      # @!attribute [r] client
      #   @return [Redis,ConnectionPool] The Redis instance or a ConnectionPool
      #     used to connect to Redis. Default `::Redis.new`
      # @!attribute [r] key_prefix
      #   @return [String] A string prepended to all Redis keys used to store
      #     circuit state. Default `faulty`.
      # @!attribute [r] key_separator
      #   @return [String] A string used to separate the parts of the Redis keys
      #     used to store circuit state. Defaulty `:`.
      # @!attribute [r] max_sample_size
      #   @return [Integer] The number of cache run entries to keep in memory
      #     for each circuit. Default `100`.
      # @!attribute [r] sample_ttl
      #   @return [Integer] The maximum number of seconds to store a
      #     circuit run history entry. Default `100`.
      # @!attribute [r] circuit_ttl
      #   @return [Integer] The maximum number of seconds to keep a circuit.
      #     A value of `nil` disables circuit expiration. This does not apply to
      #     locks, which have an indefinite storage time.
      #     Default `604_800` (1 week).
      # @!attribute [r] list_granularity
      #   @return [Integer] The number of seconds after which a new set is
      #     created to store circuit names. The old set is kept until
      #     circuit_ttl expires. Default `3600` (1 hour).
      # @!attribute [r] disable_warnings
      #   @return [Boolean] By default, this class warns if the client options
      #     are outside the recommended values. Set to true to disable these
      #     warnings.
      Options = Struct.new(
        :client,
        :key_prefix,
        :key_separator,
        :max_sample_size,
        :sample_ttl,
        :circuit_ttl,
        :list_granularity,
        :disable_warnings
      ) do
        include ImmutableOptions

        private

        def defaults
          {
            key_prefix: 'faulty',
            key_separator: ':',
            max_sample_size: 100,
            sample_ttl: 1800,
            circuit_ttl: 604_800,
            list_granularity: 3600,
            disable_warnings: false
          }
        end

        def required
          %i[list_granularity]
        end

        def finalize
          self.client = ::Redis.new(timeout: 1) unless client
        end
      end

      # @param options [Hash] Attributes for {Options}
      # @yield [Options] For setting options in a block
      def initialize(**options, &block)
        @options = Options.new(options, &block)

        check_client_options!
      end

      # Add an entry to storage
      #
      # @see Interface#entry
      # @param (see Interface#entry)
      # @return (see Interface#entry)
      def entry(circuit, time, success)
        key = entries_key(circuit)
        pipe do |r|
          r.sadd(list_key, circuit.name)
          r.expire(list_key, options.circuit_ttl + options.list_granularity) if options.circuit_ttl
          r.lpush(key, "#{time}#{ENTRY_SEPARATOR}#{success ? 1 : 0}")
          r.ltrim(key, 0, options.max_sample_size - 1)
          r.expire(key, options.sample_ttl) if options.sample_ttl
        end

        status(circuit)
      end

      # Mark a circuit as open
      #
      # @see Interface#open
      # @param (see Interface#open)
      # @return (see Interface#open)
      def open(circuit, opened_at)
        redis do |r|
          opened = compare_and_set(r, state_key(circuit), ['closed', nil], 'open', ex: options.circuit_ttl)
          r.set(opened_at_key(circuit), opened_at, ex: options.circuit_ttl) if opened
          opened
        end
      end

      # Mark a circuit as reopened
      #
      # @see Interface#reopen
      # @param (see Interface#reopen)
      # @return (see Interface#reopen)
      def reopen(circuit, opened_at, previous_opened_at)
        redis do |r|
          compare_and_set(r, opened_at_key(circuit), [previous_opened_at.to_s], opened_at, ex: options.circuit_ttl)
        end
      end

      # Mark a circuit as closed
      #
      # @see Interface#close
      # @param (see Interface#close)
      # @return (see Interface#close)
      def close(circuit)
        redis do |r|
          closed = compare_and_set(r, state_key(circuit), ['open'], 'closed', ex: options.circuit_ttl)
          r.del(entries_key(circuit)) if closed
          closed
        end
      end

      # Lock a circuit open or closed
      #
      # The circuit_ttl does not apply to locks
      #
      # @see Interface#lock
      # @param (see Interface#lock)
      # @return (see Interface#lock)
      def lock(circuit, state)
        redis { |r| r.set(lock_key(circuit), state) }
      end

      # Unlock a circuit
      #
      # @see Interface#unlock
      # @param (see Interface#unlock)
      # @return (see Interface#unlock)
      def unlock(circuit)
        redis { |r| r.del(lock_key(circuit)) }
      end

      # Reset a circuit
      #
      # @see Interface#reset
      # @param (see Interface#reset)
      # @return (see Interface#reset)
      def reset(circuit)
        pipe do |r|
          r.del(
            entries_key(circuit),
            opened_at_key(circuit),
            lock_key(circuit)
          )
          r.set(state_key(circuit), 'closed', ex: options.circuit_ttl)
        end
      end

      # Get the status of a circuit
      #
      # @see Interface#status
      # @param (see Interface#status)
      # @return (see Interface#status)
      def status(circuit)
        futures = {}
        pipe do |r|
          futures[:state] = r.get(state_key(circuit))
          futures[:lock] = r.get(lock_key(circuit))
          futures[:opened_at] = r.get(opened_at_key(circuit))
          futures[:entries] = r.lrange(entries_key(circuit), 0, -1)
        end

        Faulty::Status.from_entries(
          map_entries(futures[:entries].value),
          state: futures[:state].value&.to_sym || :closed,
          lock: futures[:lock].value&.to_sym,
          opened_at: futures[:opened_at].value ? futures[:opened_at].value.to_i : nil,
          options: circuit.options
        )
      end

      # Get the circuit history up to `max_sample_size`
      #
      # @see Interface#history
      # @param (see Interface#history)
      # @return (see Interface#history)
      def history(circuit)
        entries = redis { |r| r.lrange(entries_key(circuit), 0, -1) }
        map_entries(entries).reverse
      end

      # List all unexpired circuits
      #
      # @return (see Interface#list)
      def list
        redis { |r| r.sunion(*all_list_keys) }
      end

      # Redis storage is not fault-tolerant
      #
      # @return [true]
      def fault_tolerant?
        false
      end

      private

      # Generate a key from its parts
      #
      # @return [String] The key
      def key(*parts)
        [options.key_prefix, *parts].join(options.key_separator)
      end

      def ckey(circuit, *parts)
        key('circuit', circuit.name, *parts)
      end

      # @return [String] The key for circuit state
      def state_key(circuit)
        ckey(circuit, 'state')
      end

      # @return [String] The key for circuit run history entries
      def entries_key(circuit)
        ckey(circuit, 'entries')
      end

      # @return [String] The key for circuit locks
      def lock_key(circuit)
        ckey(circuit, 'lock')
      end

      # @return [String] The key for circuit opened_at
      def opened_at_key(circuit)
        ckey(circuit, 'opened_at')
      end

      # Get the current key to add circuit names to
      def list_key
        key('list', current_list_block)
      end

      # Get all active circuit list keys
      #
      # We use a rolling list of redis sets to store circuit names. This way we
      # can maintain this index, while still using Redis to expire old circuits.
      # Whenever we add a circuit to the list, we add it to the current set. A
      # new set is created every `options.list_granularity` seconds.
      #
      # When reading the list, we union all sets together, which gets us the
      # full list.
      #
      # Each set has its own expiration, so that the oldest sets will
      # automatically be deleted from Redis after `options.circuit_ttl`.
      #
      # It is possible for a single circuit name to be a part of many of these
      # sets. This is the space trade-off we make in exchange for automatic
      # expiration.
      #
      # @return [Array<String>] An array of redis keys for circuit name sets
      def all_list_keys
        num_blocks = (options.circuit_ttl.to_f / options.list_granularity).floor + 1
        start_block = current_list_block - num_blocks + 1
        num_blocks.times.map do |i|
          key('list', start_block + i)
        end
      end

      # Get the block number for the current list set
      #
      # @return [Integer] The current block number
      def current_list_block
        (Faulty.current_time.to_f / options.list_granularity).floor
      end

      # Set a value in Redis only if it matches a list of current values
      #
      # @param redis [Redis] The redis connection
      # @param key [String] The redis key to CAS
      # @param old [Array<String>] A list of previous values that pass the
      #   comparison
      # @param new [String] The new value to set if the compare passes
      # @return [Boolean] True if the value was set to `new`, false if the CAS
      #   failed
      def compare_and_set(redis, key, old, new, ex:)
        redis.watch(key) do
          if old.include?(redis.get(key))
            result = redis.multi { |m| m.set(key, new, ex: ex) }
            result && result[0] == 'OK'
          else
            redis.unwatch
            false
          end
        end
      end

      # Yield a Redis connection
      #
      # @yield [Redis] Yields the connection to the block
      # @return The value returned from the block
      def redis
        if options.client.respond_to?(:with)
          options.client.with { |redis| yield redis }
        else
          yield options.client
        end
      end

      # Yield a pipelined Redis connection
      #
      # @yield [Redis::Pipeline] Yields the connection to the block
      # @return [void]
      def pipe
        redis { |r| r.pipelined { |p| yield p } }
      end

      # Map raw Redis history entries to Faulty format
      #
      # @see Storage::Interface
      # @param raw_entries [Array<String>] The raw Redis entries
      # @return [Array<Array>] The Faulty-formatted entries
      def map_entries(raw_entries)
        raw_entries.map do |e|
          time, state = e.split(ENTRY_SEPARATOR)
          [time.to_i, state == '1']
        end
      end

      def check_client_options!
        return if options.disable_warnings

        check_redis_options!
        check_pool_options!
      rescue StandardError => e
        warn "Faulty error while checking client options: #{e.message}"
      end

      def check_redis_options!
        ropts = redis { |r| r.instance_variable_get(:@client).options }

        bad_timeouts = {}
        %i[connect_timeout read_timeout write_timeout].each do |time_opt|
          bad_timeouts[time_opt] = ropts[time_opt] if ropts[time_opt] > 2
        end

        unless bad_timeouts.empty?
          warn <<~MSG
            Faulty recommends setting Redis timeouts <= 2 to prevent cascading
            failures when evaluating circuits. Your options are:
            #{bad_timeouts}
          MSG
        end

        if ropts[:reconnect_attempts] > 1
          warn <<~MSG
            Faulty recommends setting Redis reconnect_attempts to <= 1 to
            prevent cascading failures. Your setting is #{ropts[:reconnect_attempts]}
          MSG
        end
      end

      def check_pool_options!
        if options.client.class.name == 'ConnectionPool'
          timeout = options.client.instance_variable_get(:@timeout)
          warn(<<~MSG) if timeout > 2
            Faulty recommends setting ConnectionPool timeouts <= 2 to prevent
            cascading failures when evaluating circuits. Your setting is #{timeout}
          MSG
        end
      end
    end
  end
end
