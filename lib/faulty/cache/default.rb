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
      extend Forwardable

      def initialize
        @cache = if defined?(::Rails)
          Cache::Rails.new(::Rails.cache)
        elsif defined?(::ActiveSupport::Cache::MemoryStore)
          Cache::Rails.new(ActiveSupport::Cache::MemoryStore.new, fault_tolerant: true)
        else
          Cache::Null.new
        end
      end

      # @!method read(key)
      #   (see Faulty::Cache::Interface#read)
      #
      # @!method write(key, value, expires_in: expires_in)
      #   (see Faulty::Cache::Interface#write)
      #
      # @!method fault_tolerant
      #   (see Faulty::Cache::Interface#fault_tolerant?)
      def_delegators :@cache, :read, :write, :fault_tolerant?
    end
  end
end
