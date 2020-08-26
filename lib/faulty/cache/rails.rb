# frozen_string_literal: true

module Faulty
  module Cache
    # A wrapper for a Rails or ActiveSupport cache
    #
    class Rails
      # @param cache The Rails cache to wrap
      # @param fault_tolerant [Boolean] Whether the Rails cache is
      #   fault_tolerant. See {#fault_tolerant?} for more details
      def initialize(cache = ::Rails.cache, fault_tolerant: false)
        @cache = cache
        @fault_tolerant = fault_tolerant
      end

      # (see Interface#read)
      def read(key)
        @cache.read(key)
      end

      # (see Interface#read)
      def write(key, value, expires_in: nil)
        @cache.write(key, value, expires_in: expires_in)
      end

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
