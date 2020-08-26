# frozen_string_literal: true

module Faulty
  module Cache
    # A mock cache for testing
    #
    # This never clears expired values from memory, and should not be used
    # in production applications. Instead, use a more robust implementation like
    # `ActiveSupport::Cache::MemoryStore`.
    class Mock
      def initialize
        @cache = {}
        @expires = {}
      end

      # Read `key` from the cache
      #
      # @return [Object, nil] The value if present and not expired
      def read(key)
        return if @expires[key] && @expires[key] < Faulty.current_time

        @cache[key]
      end

      # Write `key` to the cache with an optional expiration
      #
      # @return [void]
      def write(key, value, expires_in: nil)
        @cache[key] = value
        @expires[key] = Faulty.current_time + expires_in unless expires_in.nil?
      end

      # @return [true]
      def fault_tolerant?
        true
      end
    end
  end
end
