# frozen_string_literal: true

module Faulty
  module Cache
    class Rails
      def initialize(cache = ::Rails.cache)
        @cache = cache
      end

      def read(key)
        @cache.read(key)
      end

      def write(key, value, expires_in: nil)
        @cache.write(key, value, expires_in: expires_in)
      end

      def fault_tolerant?
        false
      end
    end
  end
end
