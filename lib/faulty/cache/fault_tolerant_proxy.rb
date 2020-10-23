# frozen_string_literal: true

class Faulty
  module Cache
    # A wrapper for cache backends that may raise errors
    #
    # {Faulty#initialize} automatically wraps all non-fault-tolerant cache backends with
    # this class.
    #
    # If the cache backend raises a `StandardError`, it will be captured and
    # sent to the notifier. Reads errors will return `nil`, and writes will be
    # a no-op.
    class FaultTolerantProxy
      attr_reader :options

      # Options for {FaultTolerantProxy}
      #
      # @!attribute [r] notifier
      #   @return [Events::Notifier] A Faulty notifier
      Options = Struct.new(
        :notifier
      ) do
        include ImmutableOptions

        private

        def required
          %i[notifier]
        end
      end

      # @param cache [Cache::Interface] The cache backend to wrap
      # @param options [Hash] Attributes for {Options}
      # @yield [Options] For setting options in a block
      def initialize(cache, **options, &block)
        @cache = cache
        @options = Options.new(options, &block)
      end

      # Wrap a cache in a FaultTolerantProxy unless it's already fault tolerant
      #
      # @param cache [Cache::Interface] The cache to maybe wrap
      # @return [Cache::Interface] The original cache or a {FaultTolerantProxy}
      def self.wrap(cache, **options, &block)
        return cache if cache.fault_tolerant?

        new(cache, **options, &block)
      end

      # Read from the cache safely
      #
      # If the backend raises a `StandardError`, this will return `nil`.
      #
      # @param (see Cache::Interface#read)
      # @return [Object, nil] The value if found, or nil if not found or if an
      #   error was raised.
      def read(key)
        @cache.read(key)
      rescue StandardError => e
        options.notifier.notify(:cache_failure, key: key, action: :read, error: e)
        nil
      end

      # Write to the cache safely
      #
      # If the backend raises a `StandardError`, the write will be ignored
      #
      # @param (see Cache::Interface#write)
      # @return [void]
      def write(key, value, expires_in: nil)
        @cache.write(key, value, expires_in: expires_in)
      rescue StandardError => e
        options.notifier.notify(:cache_failure, key: key, action: :write, error: e)
        nil
      end

      # This cache makes any cache fault tolerant, so this is always `true`
      #
      # @return [true]
      def fault_tolerant?
        true
      end
    end
  end
end
