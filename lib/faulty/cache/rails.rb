# frozen_string_literal: true

class Faulty
  module Cache
    # A wrapper for a Rails or ActiveSupport cache
    #
    class Rails
      extend Forwardable

      # @param cache The Rails cache to wrap
      # @param fault_tolerant [Boolean] Whether the Rails cache is
      #   fault_tolerant. See {#fault_tolerant?} for more details
      def initialize(cache = ::Rails.cache, fault_tolerant: false)
        @cache = cache
        @fault_tolerant = fault_tolerant
      end

      # @!method read(key)
      #   (see Faulty::Cache::Interface#read)
      #
      # @!method write(key, value, expires_in: expires_in)
      #   (see Faulty::Cache::Interface#write)
      def_delegators :@cache, :read, :write

      # Although ActiveSupport cache implementations are fault-tolerant,
      # Rails.cache is not guranteed to be fault tolerant. For this reason,
      # we require the user of this class to explicitly mark this cache as
      # fault-tolerant using the {#initialize} parameter.
      #
      # @return [Boolean]
      def fault_tolerant?
        @fault_tolerant
      end
    end
  end
end
