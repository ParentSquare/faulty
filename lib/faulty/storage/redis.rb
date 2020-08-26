# frozen_string_literal: true

module Faulty
  module Storage
    class Redis # rubocop:disable Metrics/ClassLength
      ENTRY_SEPARATOR = ':'

      attr_reader :options

      Options = Struct.new(:client, :key_prefix, :key_separator, :max_sample_size, :sample_ttl) do
        include ImmutableOptions

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

      def initialize(**options, &block)
        @options = Options.new(options, &block)
      end

      # @return [Status]
      def entry(circuit, time, success)
        key = entries_key(circuit)
        pipe do |r|
          r.lpush(key, "#{time}#{ENTRY_SEPARATOR}#{success ? 1 : 0}")
          r.ltrim(key, 0, options.max_sample_size - 1)
          r.expire(key, options.sample_ttl) if options.sample_ttl
        end

        status(circuit)
      end

      # @return [Boolean] True if the circuit transitioned from closed to open
      def open(circuit, opened_at)
        opened = nil
        redis do |r|
          opened = compare_and_set(r, state_key(circuit), ['closed', nil], 'open')
          r.set(opened_at_key(circuit), opened_at) if opened
        end
        opened
      end

      # @return [Boolean] True if the circuit transitioned from closed to open
      def reopen(circuit, opened_at, previous_opened_at)
        reopened = nil
        redis do |r|
          reopened = compare_and_set(r, opened_at_key(circuit), [previous_opened_at.to_s], opened_at)
        end
        reopened
      end

      # @return [Boolean] True if the circuit transitioned from open to closed
      def close(circuit)
        closed = nil
        redis do |r|
          closed = compare_and_set(r, state_key(circuit), ['open'], 'closed')
          r.del(entries_key(circuit)) if closed
        end
        closed
      end

      def lock(circuit, state)
        redis { |r| r.set(lock_key(circuit), state) }
      end

      def unlock(circuit)
        redis { |r| r.del(lock_key(circuit)) }
      end

      def reset(circuit)
        redis do |r|
          r.del(
            state_key(circuit),
            entries_key(circuit),
            opened_at_key(circuit),
            lock_key(circuit)
          )
        end
      end

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

      def history(circuit)
        entries = redis { |r| r.lrange(entries_key(circuit), 0, -1) }
        map_entries(entries).reverse
      end

      def fault_tolerant?
        false
      end

      private

      def key(circuit, *parts)
        [options.key_prefix, circuit.name, *parts].join(options.key_separator)
      end

      def state_key(circuit)
        key(circuit, 'state')
      end

      def entries_key(circuit)
        key(circuit, 'entries')
      end

      def lock_key(circuit)
        key(circuit, 'lock')
      end

      def opened_at_key(circuit)
        key(circuit, 'opened_at')
      end

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

      def redis
        if options.client.respond_to?(:with)
          options.client.with { |redis| yield redis }
        else
          yield options.client
        end
      end

      def pipe
        redis { |r| r.pipelined { |p| yield p } }
      end

      def map_entries(raw_entries)
        raw_entries.map do |e|
          time, state = e.split(ENTRY_SEPARATOR)
          [time.to_i, state == '1']
        end
      end
    end
  end
end
