# frozen_string_literal: true

class Faulty
  module Storage
    class ExpiringMemoryStore
      attr_reader :options

      # Options for {TtlHash}
      #
      # @!attribute [r] granularity
      #   @return [Integer] The number of seconds between bucket rotations
      #     Default `600`.
      # @!attribute [r] ttl
      #   @return [Integer] The number of seconds to keep an unused value
      #     Default `3600`.
      Options = Struct.new(:granularity, :ttl) do
        include ImmutableOptions

        def num_buckets
          ttl / granularity
        end

        private

        def defaults
          { granularity: 600, ttl: 3600 }
        end

        def finalize
          if num_buckets != ttl.to_f / granularity
            raise ArgumentError, 'ttl must be divisible by granularity'
          end
        end

        def required
          %i[granularity ttl]
        end
      end

      def initialize(**options, &block)
        @options = Options.new(**options, &block)
        @buckets = Array.new(@options.num_buckets)
        @buckets[0] = {}
        @start_time = Faulty.current_time
        @current_bucket = 0
        @mutex = Mutex.new
        @ids = {}
        @keys = {}

        @remove_id = lambda do |hashval_obj_id|
          key = @keys.delete(hashval_obj_id)
          @ids.delete(key) if key
        end
      end

      # @key The key to lookup
      # @yield A block to compute the value if absent
      def compute_if_absent(key, &block)
        bucket = calculate_bucket

        @mutex.lock
        hashval = lookup(bucket, key)
        if hashval
          @mutex.unlock
          return hashval.val
        end

        computed = block.call
        set(bucket, key, computed)
        @mutex.unlock
        computed
      end

      def delete(key)
        @mutex.synchronize do
          id = @ids.delete(key)
          @keys.delete(id)
          @buckets.each { |b| b&.delete(key) }
        end
      end

      def keys
        @mutex.synchronize do
          keys = []
          @ids.map do |(key, id)|
            keys << key unless deref(id).expired?(options.ttl)
          end
          keys
        end
      end

      private

      def lookup(bucket, key)
        object_id = @ids[key]
        return unless object_id

        hashval = deref(@ids[key])
        return if hashval.expired?(options.ttl)

        @buckets[bucket][key] = hashval
        hashval
      end

      def set(bucket, key, value)
        hashval = HashVal.new(value)
        ObjectSpace.define_finalizer(hashval, @remove_id)

        @buckets[bucket][key] = hashval
        @ids[key] = hashval.object_id
        @keys[hashval.object_id] = key
      end

      def deref(id)
        ObjectSpace._id2ref(id)
      rescue RangeError
        nil
      end

      def calculate_bucket
        elapsed = Faulty.current_time - @start_time
        bucket_for_now = (elapsed / options.granularity)

        until @current_bucket == bucket_for_now
          @current_bucket += 1
          @buckets[@current_bucket % @buckets.size] = {}
        end

        @current_bucket % @buckets.size
      end

      # We need a wrapper object for values for two reasons
      #
      # - To hold the expiry information
      # - So that the key/value can be GC'd even if there is an external
      #   reference to the value
      # @private
      class HashVal
        def initialize(val)
          @val = val
          set_time
        end

        def val
          set_time
          @val
        end

        def expired?(ttl)
          Faulty.current_time >= @time + ttl
        end

        private

        def set_time
          @time = Faulty.current_time
        end
      end
    end
  end
end
