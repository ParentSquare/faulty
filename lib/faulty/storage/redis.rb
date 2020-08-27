# frozen_string_literal: true

module Faulty
  module Storage
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
      Options = Struct.new(
        :client,
        :key_prefix,
        :key_separator,
        :max_sample_size,
        :sample_ttl
      ) do
        include ImmutableOptions

        private

        def defaults
          {
            key_prefix: 'faulty',
            key_separator: ':',
            max_sample_size: 100,
            sample_ttl: 1800
          }
        end

        def finalize
          self.client = ::Redis.new unless client
        end
      end

      # @param options [Hash] Attributes for {Options}
      # @yield [Options] For setting options in a block
      def initialize(**options, &block)
        @options = Options.new(options, &block)
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
        opened = nil
        redis do |r|
          opened = compare_and_set(r, state_key(circuit), ['closed', nil], 'open')
          r.set(opened_at_key(circuit), opened_at) if opened
        end
        opened
      end

      # Mark a circuit as reopened
      #
      # @see Interface#reopen
      # @param (see Interface#reopen)
      # @return (see Interface#reopen)
      def reopen(circuit, opened_at, previous_opened_at)
        reopened = nil
        redis do |r|
          reopened = compare_and_set(r, opened_at_key(circuit), [previous_opened_at.to_s], opened_at)
        end
        reopened
      end

      # Mark a circuit as closed
      #
      # @see Interface#close
      # @param (see Interface#close)
      # @return (see Interface#close)
      def close(circuit)
        closed = nil
        redis do |r|
          closed = compare_and_set(r, state_key(circuit), ['open'], 'closed')
          r.del(entries_key(circuit)) if closed
        end
        closed
      end

      # Lock a circuit open or closed
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
          r.set(state_key(circuit), 'closed')
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

      def list
        redis { |r| r.smembers(list_key) }
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
      def key(circuit, *parts)
        [options.key_prefix, circuit.name, *parts].join(options.key_separator)
      end

      # @return [String] The key for circuit state
      def state_key(circuit)
        key(circuit, 'state')
      end

      # @return [String] The key for circuit run history entries
      def entries_key(circuit)
        key(circuit, 'entries')
      end

      # @return [String] The key for circuit locks
      def lock_key(circuit)
        key(circuit, 'lock')
      end

      # @return [String] The key for circuit opened_at
      def opened_at_key(circuit)
        key(circuit, 'opened_at')
      end

      def list_key
        [options.key_prefix, 'list'].join(options.key_separator)
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
      def compare_and_set(redis, key, old, new)
        result = redis.watch(key) do
          if old.include?(redis.get(key))
            redis.multi { |m| m.set(key, new) }
          else
            redis.unwatch
          end
        end

        result[0] == 'OK'
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
    end
  end
end
