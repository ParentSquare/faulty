# frozen_string_literal: true

class Faulty
  module Cache
    # Automatically configure a cache backend
    #
    # Used by {Faulty#initialize} to setup sensible cache defaults
    class AutoWire
      extend Forwardable

      # Options for {AutoWire}
      Options = Struct.new(
        :notifier
      ) do
        include ImmutableOptions

        private

        def required
          %i[notifier]
        end
      end

      # Wrap a cache backend with sensible defaults
      #
      # If the cache is `nil`, create a new {Default}.
      #
      # If the backend is not fault tolerant, wrap it in {CircuitProxy} and
      # {FaultTolerantProxy}.
      #
      # @param cache [Interface] A cache backend
      # @param options [Hash] Attributes for {Options}
      # @yield [Options] For setting options in a block
      def initialize(cache, **options, &block)
        @options = Options.new(options, &block)
        @cache = if cache.nil?
          Cache::Default.new
        elsif cache.fault_tolerant?
          cache
        else
          Cache::FaultTolerantProxy.new(
            Cache::CircuitProxy.new(cache, notifier: @options.notifier),
            notifier: @options.notifier
          )
        end

        freeze
      end

      # @!method read(key)
      #   (see Faulty::Cache::Interface#read)
      #
      # @!method write(key, value, expires_in: expires_in)
      #   (see Faulty::Cache::Interface#write)
      def_delegators :@cache, :read, :write

      # Auto-wired caches are always fault tolerant
      #
      # @return [true]
      def fault_tolerant?
        true
      end
    end
  end
end
