# frozen_string_literal: true

class Faulty
  module Cache
    # The default cache implementation
    #
    # It tries to make a logical decision of what cache implementation to use
    # based on the current environment.
    #
    # - If Rails is loaded, it will use Rails.cache
    # - If ActiveSupport is available, it will use an `ActiveSupport::Cache::MemoryStore`
    # - Otherwise it will use a {Faulty::Cache::Null}
    class Default
      def initialize
        @cache = if defined?(::Rails)
          Cache::Rails.new(::Rails.cache)
        elsif defined?(::ActiveSupport::Cache::MemoryStore)
          Cache::Rails.new(ActiveSupport::Cache::MemoryStore.new, fault_tolerant: true)
        else
          Cache::Null.new
        end
      end

      # Read from the internal cache by key
      #
      # @param (see Cache::Interface#read)
      # @return (see Cache::Interface#read)
      def read(key)
        @cache.read(key)
      end

      # Write to the internal cache
      #
      # @param (see Cache::Interface#read)
      # @return (see Cache::Interface#read)
      def write(key, value, expires_in: nil)
        @cache.write(key, value, expires_in: expires_in)
      end

      # This cache is fault tolerant if the internal one is
      #
      # @return [Boolean]
      def fault_tolerant?
        @cache.fault_tolerant?
      end
    end
  end
end
