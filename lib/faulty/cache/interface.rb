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
        raise NotImplementedError
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
        raise NotImplementedError
      end

      # Can this cache backend raise an error?
      #
      # If the cache backend returns false from this method, it will be wrapped
      # in a {FaultTolerantProxy}, otherwise it will be used as-is.
      #
      # @return [Boolean] True if this cache backend is fault tolerant
      def fault_tolerant?
        raise NotImplementedError
      end
    end
  end
end
