# frozen_string_literal: true

module Faulty
  module Cache
    # The interface required for a cache backend implementation
    #
    # This is for documentation only and is not loaded
    class Interface
      # Retrieve a value from the cache if available
      #
      # @param key [String] The cache key
      # @raise If the cache backend encounters a failure
      # @return [Object, nil] The object if present, otherwise nil
      def read(key)
      end

      # Write a value to the cache
      #
      # This may be any object. It's up to the cache implementation to
      # serialize if necessary or raise an error if unsupported.
      #
      # @param key [String] The cache key
      # @param expires_in [Integer, nil] The number of seconds until this cache
      #   entry expires. If nil, no expiration is set.
      # @param value [Object] The value to write to the cache
      # @raise If the cache backend encounters a failure
      # @return [void]
      def write(key, value, expires_in: nil)
      end

      def fault_tolerant?
      end
    end
  end
end
