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
          r.lpush(key, "#{time.to_i}#{ENTRY_SEPARATOR}#{success ? 1 : 0}")
          r.ltrim(key, 0, options.max_sample_size - 1)
          r.expire(key, options.sample_ttl) if options.sample_ttl
        end

        status(circuit)
      end

      # @return [Boolean] True if the circuit transitioned from closed to open
      def open(circuit)
        opened = nil
        redis do |r|
          opened = compare_and_set(r, state_key(circuit), ['closed', nil], 'open')
          r.set(opened_at_key(circuit), Faulty.current_time.to_i)
        end
        opened
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

        stats = compute_stats(circuit, map_entries(futures[:entries].value))
        Faulty::Status.new(stats.merge(
          state: futures[:state].value&.to_sym || :closed,
          lock: futures[:lock].value&.to_sym,
          opened_at: futures[:opened_at].value ? Time.at(futures[:opened_at].value.to_i).utc : nil,
          cool_down: circuit.options.cool_down,
          sample_threshold: circuit.options.sample_threshold,
          rate_threshold: circuit.options.rate_threshold
        ))
      end

      def history(circuit)
        entries = redis { |r| r.lrange(entries_key(circuit), 0, -1) }
        map_entries(entries)
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
          [Time.at(time.to_i).utc, state == '1']
        end
      end

      def compute_stats(circuit, entries)
        stats = { sample_size: 0 }
        failures = 0
        entries.each do |(time, success)|
          next unless time > Faulty.current_time - circuit.options.evaluation_window

          stats[:sample_size] += 1
          failures += 1 unless success
        end
        stats[:failure_rate] = stats[:sample_size].zero? ? 0.0 : failures.to_f / stats[:sample_size]
        stats
      end
    end
  end
end
